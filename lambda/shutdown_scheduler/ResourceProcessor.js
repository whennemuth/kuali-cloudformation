
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

function ExperimentChecker(event) {
  this.hasExperiments = () => {
    return event && event.experiment;
  }
  this.runExperiments = () => {
    const Experiment = require('./debugExperiment');
    for (const trialName in event.experiment) {
      if (Object.hasOwnProperty.call(event.experiment, trialName)) {
        const trialArg = event.experiment[trialName];
        Experiment.runTrial(trialName, trialArg);
      }
    }
  }
}

exports.handler = function (event, context) {
  try {
    const experimentCheck = new ExperimentChecker(event);
    if(experimentCheck.hasExperiments()) {
      experimentCheck.runExperiments();
      return;
    }

    var tagging = {
      timezoneTag: process.env.TimeZoneKey,
      lastRebootTag: process.env.LastRebootTimeKey,
      cron: {
        startTag: process.env.StartupCronKey,
        stopTag: process.env.ShutdownCronKey,
        rebootTag: process.env.RebootCronKey
      }
    };

    console.log("Resources qualify for shutdown/startup with tagging as follows:");
    console.log(JSON.stringify(tagging, null, 2));

    new ResourceCollection.load(AWS, tagging, (candidates) => {
      if(candidates.processNext) {
        candidates.processNext((resource, callback) => {
          var scheduled = new ScheduledResource(AWS, resource);
          console.log("");
          console.log("---------");
          console.log(resource.getIntroduction());
          console.log("---------");
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
                  scheduled.toReboot((reboot) => {
                    if(reboot) {
                      resource.reboot(callback);
                    }
                    else {
                      callback(resource);
                    }
                  })                  
                }
              })
            }
          });
        },
        () => {
          console.log('\nFinished processing.\n');
          console.log('@'.repeat(100));
        });
      }
    });
  }
  catch(e) {
    e.stack ? console.error(e, e.stack) : console.error(e);
  }
}