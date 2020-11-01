try {
  var AWS = require('aws-sdk');
  var response = require('./cfn-response');
}
catch(e){
  var AWS = require('./mock-aws-sdk');
  var response = require('./mock-cfn-response');
}

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
   *    WAF_ARN
   */
  this.processor = function () {
    this.setResource = (r) => { this.resource = r; };
    this.setTarget = (t) => { this.target = t; };
    this.failMessage = '';

    this.start = () => {
      (new this.tasks(this)).nextTask();
    };

    this.isEligible = function(task) {
      if(this.resource && this.resource != task.resource) return false;
      if(this.target && this.target != task.target) return false;
      return true;
    };

    this.emptyBucket = function(bucketName, callback) {
      var s3 = new AWS.S3();
      var bucket = this;
      bucket.counter = 0;
      console.log('Emptying bucket: ' + bucketName + '...');

      this.delete = function(items, bucketName, callback) { 
        var deleteParams = { Bucket: bucketName, Key: items[bucket.counter].Key }; 
        bucket.counter++; 
        console.log('DELETING ' + JSON.stringify(deleteParams) + '...');
        
        s3.deleteObject(deleteParams, function (err, data) {
          if (err) {
            console.log("ERROR: Cannot delete " + deleteParams.Key);
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
          console.log("ERROR: Cannot list bucket objects: " + err);
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

    this.tasks = function(processor) {

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
          console.log('DISABLING ALB LOGGING FOR: ' + process.env.LOAD_BALANCER_ARN + '...');
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
          console.log('DISABLING WAF LOGGING FOR: ' + process.env.WAF_ARN + '...');
          var wafv2 = new AWS.WAFV2();
          wafv2.deleteLoggingConfiguration({ResourceArn: process.env.WAF_ARN}, function(err, data) {
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

  if (event.RequestType && event.RequestType.toUpperCase() == "DELETE") {
    try {       
      var proc = new this.processor();
      proc.setResource(event.ResourceProperties.resource);
      proc.setTarget(event.ResourceProperties.target);
      proc.start();
    }
    catch(e) {
      var msg = e.name + ': ' + e.message;
      console.log(msg);
      if(e.stack) {
        console.log(e.stack);
      }
      response.send(event, context, response.SUCCESS, { Reply: msg });
    }
  }
  else {
    console.log('Stack operation is: ' + event.RequestType + ', skipping lambda execution...');
    response.send(event, context, response.SUCCESS, { Reply: 'skipped' });
  }
};

