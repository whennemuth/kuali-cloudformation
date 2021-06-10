
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
      filters: {},
      cron: {
        start: process.env.StartupCronKey,
        stop: process.env.ShutdownCronKey
      }
    };

    if(process.env.Service) {
      tagging.filters.Service = process.env.Service;
    }
    if(process.env.Function) {
      tagging.filters.Function = process.env.Service;
    }
    for(var i=1; i<=5; i++) {
      if(process.env[`Tag${i}`]) {
        var tag = JSON.parse(process.env[`Tag${i}`]);
        tagging.filters[tag.key] = tag.value;
      }
    }

    new ResourceCollection.load(AWS, tagging, (candidates) => {
      if(candidates.processNext) {
        candidates.processNext((resource, callback) => {
          var scheduled = new ScheduledResource(resource);
          console.log("");
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
          console.log('\nFinished processing.');
        });
      }
    });
  }
  catch(e) {
    e.stack ? console.error(e, e.stack) : console.error(e);
  }
}