
const ResourceCollection = require('./ResourceCollection');
const ScheduledResource = require('./ResourceDecoratorForScheduling');

switch(process.env.DEBUG_MODE) {
  case 'local_mocked':
    var AWS = require('./mock-aws-sdk');
    break;
  case 'local_unmocked':
    var AWS = require('aws-sdk');
    break;
  default:
    var AWS = require('aws-sdk');
    break;
}

exports.handler = function (event, context) {
  try {
    // console.log("ENVIRONMENT VARIABLES\n" + JSON.stringify(process.env, null, 2))
    // console.info("EVENT\n" + JSON.stringify(event, null, 2))

    var tagging = {
      filters: {
        Service: "research-administration",
        Function: "kuali"
      },
      cron: {
        start: "StartupCron",
        stop: "ShutdownCron"
      }
    };

    new ResourceCollection.load(AWS, tagging, (candidates) => {
      if(candidates.processNext) {
        candidates.processNext((resource, callback) => {
          var scheduled = new ScheduledResource(resource);
          scheduled.toStop((stop) => {
            if(stop) {
              resource.stop(callback);
            }
            else {
              scheduled.toStart((start) => {
                if(start) {
                  resource.start(callback);
                }
                else {
                  callback(resource);
                }
              })
            }
          });
        },
        () => {
          console.log(`Finished processing.`);
          console.log('-----------------------------------------------------------------');
        });
      }
    });
  }
  catch(e) {
    e.stack ? console.error(e, e.stack) : console.error(e);
  }
}