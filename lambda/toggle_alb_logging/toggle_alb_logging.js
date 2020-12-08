var AWS = require('aws-sdk');
var response = require('cfn-response');

const toggleAlbLogging = (albArn, enableLogs, callback) => {
  try {
    var elbv2 = new AWS.ELBv2();
    const albAttribute = 'access_logs.s3.enabled';
    var params = {
      Attributes: [{
        Key: albAttribute, 
        Value: enableLogs.toString()
      }], 
      LoadBalancerArn: albArn
    };
    console.log(`${enableLogs ? 'Enabling' : 'Disabling'} logging for ${albArn}...`);
    elbv2.modifyLoadBalancerAttributes(params, function(err, data) {
      if(err) {
        callback(e, null);
      }
      else { 
        try {
          var verified = data.Attributes.find(attribute => {
            return (attribute.Key == albAttribute && attribute.Value == enableLogs.toString());
          });
          console.log(`ALB logging ${enableLogs ? 'enabling' : 'disabling'} attempt result: ${verified ? 'Succeeded': 'Failed'}`)
          callback(null, `${verified ? 'succeeded' : 'failed' }`);
        }
        catch(e) {
          callback(e, null);
        }         
      }
    });
  }
  catch(e) {
    callback(e, null);
  }
}

const sendResponse = (event, context, responseType, result) => {
  try {
    response.send(event, context, responseType, { Reply: `${result}` });
  }
  catch(e) {
    if( process.env.DEBUG_MODE && process.env.DEBUG_MODE == 'local') {
      return;
    }
    throw(e);
  }
}

const sendErrorResponse = (event, context, err) => {
  err.stack ? console.log(err, err.stack) : console.log(err);
  var msg = err.name + ': ' + err.message;
  var toggle = (event && event.RequestType && /^delete$/i.test(event.RequestType)) ? 'disable' : 'enable';
  try {
    response.send(event, context, response.FAILED, { Reply: `Failed to ${toggle} alb logging: ${msg}, (see cloudwatch logs for detail)` });
  }
  catch(e) {
    if( process.env.DEBUG_MODE && process.env.DEBUG_MODE == 'local') {
      return;
    }
    throw(e);
  }
}

/**
 * Toggle logging for the specified alb.
 * @param {*} event 
 * @param {*} context 
 */
exports.handler = function (event, context) {
  try {
    if (/^delete$/i.test(event.RequestType)) {
      toggleAlbLogging(event.ResourceProperties.AlbArn, false, (err, result) => {
        if(err) {
          sendErrorResponse(event, context, err);
        }
        else {
          switch(result) {
            case 'succeeded':
              sendResponse(event, context, response.SUCCESS, result); break;
            default:
              sendResponse(event, context, response.FAILED, result); break;
          }          
        }
      })
    }
    else {
      console.log(`Stack operation is: ${event.RequestType}, cancelling lambda execution - enabling/disabling alb logging does not apply...'`);
      sendResponse(event, context, response.SUCCESS, { Reply: 'skipped' });
    }
  }
  catch(e) {
    sendErrorResponse(event, context, e);
  }
}