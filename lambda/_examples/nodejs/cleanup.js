// Fix this later with dependency injection.
switch(process.env.MODE) {
  case 'mocked':
    var AWS = require('./mock-aws-sdk');
    var response = require('../mock-cfn-response');
    break;
  case 'unmocked':
    var AWS = require('aws-sdk');
    var response = require('cfn-response');
    break;
  default:
    var response = require('cfn-response');
    break;
}
var getParameters = require('./parameters');

exports.handler = function (event, context) {


  /**
   * Process a series of tasks. Each task runs an async operation, completion upon which the next task is called.
   * The first task that fails will cause all subsequent tasks to be omitted.
   * These task perform "cleanup" in preparation for a stack deletion.
   * Logging to s3 buckets needs to be disabled, followed by emptying of those buckets.
   * 
   * Parameters:
   *    event.ResourceProperties.resource: 'alb', 'waf', 'athena'
   *    event.ResourceProperties.target: 'logging', 'bucket'
   * 
   * Environment:
   *    ALB_BUCKET_NAME
   *    WAF_BUCKET_NAME
   *    ATHENA_BUCKET_NAME
   *    LOAD_BALANCER_ARN
   *    WEBACL_ARN
   *    or...
   *    LANDSCAPE
   */
  this.processor = function () {
    this.setResource = (r) => { this.resource = r; };
    this.setTarget = (t) => { this.target = t; };
    this.setParameters = (p) => { this.parameters = p; };
    this.failMessage = '';

    this.start = () => {
      (new this.tasks(this)).nextTask();
    };

    this.isEligible = function(task) {
      return isEligibleTask(this.resource, this.target, task);
    };

    /**
     * Provided a bucket name, empty all of its contents. Then invoke the provided callback.
     * @param {*} bucketName 
     * @param {*} callback 
     */
    this.emptyBucket = function(bucketName, callback) {
      var s3 = new AWS.S3();
      var bucket = this;
      bucket.counter = 0;
      console.log(`Emptying bucket: ${bucketName}...`);

      this.delete = function(items, bucketName, callback) { 
        var deleteParams = { Bucket: bucketName, Key: items[bucket.counter].Key }; 
        bucket.counter++; 
        console.log('DELETING ' + JSON.stringify(deleteParams) + '...');
        
        s3.deleteObject(deleteParams, function (err, data) {
          if (err) {
            console.log(`ERROR: Cannot delete ${deleteParams.Key}`);
            console.log(err, err.stack); 
            callback(err, data) ;             
          }
          else {
            console.log(data);
            if (bucket.counter < items.length) {
              bucket.delete(items, bucketName, function(err, data) {
                callback(err, data);
              })
            }
            else {              
              callback(err, data);
            }
          }
        }
      )};

      s3.listObjects({ Bucket: bucketName }, function (err, data) {
        if (err) {
          console.log(`ERROR: Cannot list bucket objects: ${err}`);
          console.log(err, err.stack);
        }
        else if( !data || ! data.Contents || data.Contents.length == 0) {
          callback(err, data);
        }
        else {
          bucket.delete(data.Contents, bucketName, callback);
        }
      });
    };

    /**
     * This function represents a collection of all tasks, both elligible and inelligible for being executed.
     * @param {*} processor 
     */
    this.tasks = function(processor) {

      /**
       * This function executes a member task if that task indicates it is elligible, else moves on to the next task and repeats.  
       * @param {*} task 
       */
      this.nextTask = (task) => {
        if (processor.failMessage) {
          (new this.sendResponse(processor, this)).execute();
          return;
        }
        if( ! task) {
          // The very first task should be to disable alb logging.
          var task = new this.disableAlbLogging(processor, this);
          if(task.eligible()) {
            task.execute();
          }
          else {
            this.nextTask(task);
          }
          return;
        }
        while(task) {
          if(task.next) {
            task = task.next();
            if(task == 'nothing') {
              return;
            }
            if(task.eligible && task.eligible()) {
              task.execute();
              return;
            }
          }
        }
      };

      /**
       * Disable logging for the application load balancer. 
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.disableAlbLogging = function(processor, tasks) {
        this.resource = 'alb';
        this.target = 'logging';
        this.next = () => {
          return new tasks.emptyAlbLoggingBucket(processor, tasks);
        };
        this.eligible = () => {
          return processor.isEligible(this);
        };
        this.execute = function() {
          var self = this;
          console.log(`DISABLING ALB LOGGING FOR: ${processor.parameters.albArn}...`);
          var elbv2 = new AWS.ELBv2();
          var params = {
            Attributes: [{
              Key: "access_logs.s3.enabled", 
              Value: "false"
            }], 
            LoadBalancerArn: process.env.LOAD_BALANCER_ARN
          };
          elbv2.modifyLoadBalancerAttributes(params, function(err, data) {
            if(err) {
              processor.failMessage = 'Failed to disable alb logging (see cloudwatch logs for detail)';
              console.log('ERROR DISABLING ALB LOGGING...');
              console.log(err, err.stack);
            }
            else{
              console.log('ALB LOGGING DISABLED...');
              console.log(data); // successful response
            }
            tasks.nextTask(self);
          });
        }
      };

      /**
       * Disable logging for the web application firewall.
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.disableWafLogging = function(processor, tasks) {
        this.resource = 'waf';
        this.target = 'logging';
        this.next = () => {
          return new tasks.emptyWafLoggingBucket(processor, tasks);
        };
        this.eligible = () => {
          return processor.isEligible(this);
        };
        this.execute = function() {
          var self = this;
          console.log('DISABLING WAF LOGGING FOR: ' + process.env.WEBACL_ARN + '...');
          var wafv2 = new AWS.WAFV2();
          wafv2.deleteLoggingConfiguration({ResourceArn: process.env.WEBACL_ARN}, function(err, data) {
            if(err) {
              processor.failMessage = 'Failed to disable waf logging (see cloudwatch logs for detail)';
              console.log('ERROR DISABLING WAF LOGGING...');
              console.log(err, err.stack);
            }
            else {
              console.log('WAF LOGGING DISABLED...');
              console.log(data); // successful response
            }
            tasks.nextTask(self);
          });
        }        
      };

      /**
       * Empty out all items from the alb logging s3 bucket.
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.emptyAlbLoggingBucket = function(processor, tasks) {
        this.resource = 'alb';
        this.target = 'bucket';
        this.next = () => {
          return new tasks.disableWafLogging(processor, tasks);
        };
        this.eligible = () => {
          return processor.isEligible(this);
        };
        this.execute = function() {
          var self = this;
          console.log('EMPTYING ALB LOGGING BUCKET...');
          processor.emptyBucket(process.env.ALB_BUCKET_NAME, function(err, data){
            if (err) {
              processor.failMessage = 'Failed to empty alb s3 logging bucket (see cloudwatch logs for detail)';
            }
            else {
              console.log("ALB LOGGING BUCKET EMPTIED.");
            }
            tasks.nextTask(self);
          });
        };
      };

      /**
       * Empty out all items from the waf logging s3 bucket
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.emptyWafLoggingBucket = function(processor, tasks) {
        this.resource = 'waf';
        this.target = 'bucket';
        this.next = () => {
          return new tasks.emptyAthenaLoggingBucket(processor, tasks);
        };
        this.eligible = () => {
          return processor.isEligible(this);
        };
        this.execute = function() {
          var self = this;
          console.log('EMPTYING WAF LOGGING BUCKET...');
          processor.emptyBucket(process.env.WAF_BUCKET_NAME, function(err, data){
            if (err) {
              processor.failMessage = 'Failed to empty waf s3 logging bucket (see cloudwatch logs for detail)';
            }
            else {
              console.log("WAF LOGGING BUCKET EMPTIED.");
            }
            tasks.nextTask(self);
          });
        };
      };

      /**
       * Empty all items from the athena logging s3 bucket
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.emptyAthenaLoggingBucket = function(processor, tasks) {
        this.resource = 'athena';
        this.target = 'bucket';
        this.next = () => {
          return new tasks.sendResponse(processor, tasks);
        };
        this.eligible = () => {
          return processor.isEligible(this);
        };
        this.execute = function() {
          var self = this;
          console.log('EMPTYING ATHENA LOGGING BUCKET...');
          processor.emptyBucket(process.env.ATHENA_BUCKET_NAME, function(err, data){
            if (err) {
              processor.failMessage = 'Failed to empty athena s3 logging bucket (see cloudwatch logs for detail)'
            }
            else {
              console.log("ATHENA LOGGING BUCKET EMPTIED.");
            }
            tasks.nextTask(self);
          });
        };
      };

      /**
       * Send an http response back to cloudformation indicating the success/fail status after execution of tasks.
       * @param {*} processor 
       * @param {*} tasks 
       */
      this.sendResponse = function(processor, tasks) {
        this.next = () => {
          return 'nothing';
        };
        this.eligible = () => {
          return true;
        };
        this.execute = function() {
          if(processor.failMessage) {
            console.log('RETURNING FAILURE RESPONSE...');
            response.send(event, context, response.FAILURE, { Reply: processor.failMessage });
          }
          else {
            console.log('RETURNING SUCCESS RESPONSE...');
            response.send(event, context, response.SUCCESS, { Reply: 'success' });
          }
        };
      };
    }
  }

  
  /**
   * All tasks are elligible if no resource or target properties were provided to setResource() and setTarget().
   * Otherwise, anything provided to a these setters has to match the tasks corresponding attribute for that task
   * to be elligible. The more setter use, the more exclusive task elligibility will be.
   * @param {*} task 
   */
  const isEligibleTask = (resource, target, task) => {
    if(resource && resource != task.resource) return false;
    if(target && target != task.target) return false;
    return true;
  };

  this.printError = (e) => {
    var msg = e.name + ': ' + e.message;
    console.log(msg);
    if(e.stack) {
      console.log(e.stack);
    }
    return msg;
  }

  /**
   * Run all elligible tasks if cloudformation is performing a stack deletion.
   */
  if (event.RequestType && event.RequestType.toUpperCase() == "DELETE") {
    try { 
      getParameters(event, isEligibleTask, (parms) => {
        if(parms.errors.length > 0) {
          for(let i=0; i<parms.errors.length; i++) {
            var msg = this.printError(parms.errors[i]);
          }
          response.send(event, context, response.SUCCESS, { Reply: msg });
        }
        else {
          var proc = new this.processor();
          proc.setParameters(parms);
          console.log('Parameters: ' + JSON.stringify(parms, null, '  '));
          proc.setResource(event.ResourceProperties.resource);
          proc.setTarget(event.ResourceProperties.target);
          proc.start();
        }
      });
    }
    catch(e) {
      this.printError(e);
      response.send(event, context, response.SUCCESS, { Reply: msg });
    }
  }
  else {
    console.log('Stack operation is: ' + event.RequestType + ', skipping lambda execution...');
    response.send(event, context, response.SUCCESS, { Reply: 'skipped' });
  }
};

