var AWS = require('aws-sdk');
if(process.env.DEBUG == 'true') {
  var response = require('../mock-cfn-response');
}
else {
  var response = require('cfn-response');
}


exports.handler = function (event, context) {

  this.wafAdjuster = function() {

    var webAcl = {};
    var webAclLockToken = '';

    var us_only = function() {
      console.log('Adding rule to restrict access to within the US...');

      var params = {
        Id: webAcl.Id,
        LockToken: webAclLockToken,
        Name: 'Kuali_Restrict_To_USA',
        Scope: 'REGIONAL',
        Description: 'Blocks incoming request from outside the US',
        Rules: [
          {
            VisibilityConfig: {
              CloudWatchMetricsEnabled: true,
              MetricName: 'Kuali_Foreign_Blocks',
              SampledRequestsEnabled: true
            },
            Statement: {
              GeoMatchStatement: {
                CountryCodes: [ 'US' ]
              },
              Action: {
                Block: {}
              },
              OverrideAction: {
                Count: {}
              }
            } 
          }
        ]
      };

      wafv2.updateRuleGroup(params, function(err, data) {
        if (err) {
          console.log(err, err.stack);
        }
        else {
          console.log(data);
          nextTask();
        }
      });
    };

    var test_task = function() {
      console.log('hello from test task');
      nextTask();
    };

    var alltasks = [
      us_only, test_task
    ];

    var nextTask = () => {
      if(alltasks.length > 0) {
        var task = alltasks.shift();
        if(isRequested(task.name)) {
          task();
        }   
      }
    };

    var isRequested = (taskname) => {
      return /^true$/i.test(event.ResourceProperties[taskname]);
    }

    var wafv2 = new AWS.WAFV2();
    console.log('ALB: ' + process.env.ALB);

    wafv2.getWebACLForResource({ResourceArn: process.env.ALB}, function(err, data) {
      if (err) {       
        console.log(err, err.stack);
      }
      else {
        var params = {
          Id: data.WebACL.Id,
          Name: data.WebACL.Name,
          Scope: 'REGIONAL'
        };
        wafv2.getWebACL(params, function(err, data) {
          if (err) {
            console.log(err, err.stack);
          }
          else {
            webAcl = data.WebACL;
            webAclLockToken= data.LockToken;
            console.log("WebACL Name: " + webAcl.Name);
            console.log("WebACL Id: " + webAcl.Id);
            nextTask();
          }
        });
      }
    });
  };


  if (event.RequestType && /^((create)|(update))$/i.test(event.RequestType)) {
    try{
      var wafAdjuster = new this.wafAdjuster();
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
