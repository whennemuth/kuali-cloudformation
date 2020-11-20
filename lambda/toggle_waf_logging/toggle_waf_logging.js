var AWS = require('aws-sdk');
var response = require('cfn-response');


const toggleWafLogging = (webAclArn, firehoseArn, enableLogs, callback) => {
  try {
    var wafv2 = new AWS.WAFV2();
    wafv2.getLoggingConfiguration({ResourceArn: webAclArn}, function(err, data) {
      if(err) {
        console.log(`No logging configuration found for ${webAclArn}`);
        if(enableLogs) {
          console.log('Creating new waf logging configuration...');
          var params = {
            LoggingConfiguration: {
              LogDestinationConfigs: [
                firehoseArn
              ],
              ResourceArn: webAclArn
            }
          }
          wafv2.putLoggingConfiguration(params, function(err, data) {
            if(data) {
              console.log(`Logging configuration created for ${webAclArn}`);
            }
            callback(err, data);
          });
        }
        else {
          console.log('No logging configuration exists to be deleted, cancelling...');
          callback();
        }
      }
      else {
        if(enableLogs) {
          console.log('Logging configuration already exists for ${webAclArn}, cancelling...');
          callback();
        }
        else {
          console.log('Deleting existing waf logging configuration...');
          wafv2.deleteLoggingConfiguration({ResourceArn: webAclArn}, function(err, data) {
            if( ! err) {
              console.log(`Logging configuration deleted for ${webAclArn}`);
            }
            callback(err, data);
          });
        }
      }
    });
  }
  catch(e) {
    callback(e, null);
  }
}

const sendResponse = (event, context, responseType, reply) => {
  try {
    response.send(event, context, responseType, reply);
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
    response.send(event, context, response.FAILURE, { Reply: `Failed to ${toggle} waf logging: ${msg}, (see cloudwatch logs for detail)` });
  }
  catch(e) {
    if( process.env.DEBUG_MODE && process.env.DEBUG_MODE == 'local') {
      return;
    }
    throw(e);
  }
}

/**
 * Toggle logging for the specified waf.
 * @param {*} event 
 * @param {*} context 
 */
exports.handler = function (event, context) {
  try {
    if (/^(delete)|(create)$/i.test(event.RequestType)) {
      var enable = /^create$/i.test(event.RequestType)
      toggleWafLogging(event.ResourceProperties.WebAclArn, event.ResourceProperties.FirehoseArn, enable, (err, result) => {
        if(err) {
          sendErrorResponse(event, context, err);
        }
        else {
          switch(result) {
            case 'succeeded':
              sendResponse(event, context, response.SUCCESS, { Reply: `${result}` }); break;
            default:
              sendResponse(event, context, response.FAILURE, { Reply: `${result}` }); break;
          }          
        }
      })
    }
    else {
      console.log(`Stack operation is: ${event.RequestType}, cancelling lambda execution - enabling/disabling waf logging does not apply...'`);
      sendResponse(event, context, response.SUCCESS, { Reply: 'skipped' });
    }
  }
  catch(e) {
    sendErrorResponse(event, context, e);
  }
}