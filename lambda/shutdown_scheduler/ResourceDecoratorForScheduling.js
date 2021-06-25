
const Cron = require('./CronUtils');

/**
 * This function provides a wrapper functionality for a resource object, using it's tags to determine cron
 * expressions and derive schedules for start, stop, or reboot actions.
 * This scheduling is used in methods that can indicate if any of these actions need to be taken on the resource.
 * 
 * @param {*} resource 
 */
module.exports = function(AWS, resource) {

  this.resource = resource;

  this.handleError = (e, callback) => {
    e.stack ? console.error(e, e.stack) : console.error(e);
    this.error = true;
    if(callback) {
      callback(false);   
    }
  }

  try {
    this.scheduledStarts = new Cron(resource.getStartCron(), resource.getTimeZone());
    this.scheduledStops = new Cron(resource.getStopCron(), resource.getTimeZone());
    this.scheduledRebootsArray = [];
    for(var i=1; i<=10; i++) {
      let cron = resource.getRebootCron(i);
      if(cron) {
        this.scheduledRebootsArray.push(new Cron(cron, resource.getTimeZone()));
      }      
    }
    if(this.scheduledRebootsArray.length == 0) {
      // The resource has no reboot cron, but add a single dummy cron to get the proper log messaging.
      this.scheduledRebootsArray.push(new Cron(null, resource.getTimeZone()));
    }
    this.resource = resource;
  }
  catch(e) {
    this.handleError(e);
  }

  this.logMessage = (parms) => {
    if(parms.currentState == parms.desiredState) {
      if((parms.context === 'startup' && parms.desiredState === 'running') || (parms.context === 'shutdown' && parms.desiredState === 'stopped')) {
        var decision = `Leave ${this.resource.getId()} alone`;
        var reason = `Resource ${this.resource.getId()} is already ${parms.desiredState}.`;    
        // Uppercase the first letter of the context.
        let context = parms.context.charAt(0).toUpperCase() + parms.context.slice(1);
        console.log(`${context} decision: ${decision} - Reason: ${reason}`);
        return;
      }
      else {
        var decision = `Resource ${this.resource.getId()} is ${parms.currentState} and should remain that way`;
      }
    }
    else {
      var decision = `Resource ${this.resource.getId()} is ${parms.currentState} and should be ${parms.desiredState}`;
    }

    if( ! this.scheduledStops.prev()) {
      var reason = `${this.scheduledStarts.description('start')} has no future stop time.`
    }
    else if( ! this.scheduledStarts.prev()) {
      var reason = `${this.scheduledStops.description('stop')} has no future start time.`
    }
    else if(this.scheduledStops.lastMoreRecentThan(this.scheduledStarts)) {
      var reason = `${this.scheduledStops.description('stop')} is more recent than ${this.scheduledStarts.description('start')}`;
    }
    else {
      var reason = `${this.scheduledStarts.description('start')} is more recent than ${this.scheduledStops.description('stop')}`;
    }
    
    // Uppercase the first letter of the context.
    let context = parms.context.charAt(0).toUpperCase() + parms.context.slice(1);

    // Log out the decision for action to take (not take) and the reason why.
    console.log(`${context} decision: ${decision} - Reason: ${reason}`);
  }

  this.toStop = (callback) => {
    try {
      resource.isRunning((running, error) => {
        if(error) {
          callback(false);
        }
        else {
          if(running) {
            if(this.scheduledStops.lastMoreRecentThan(this.scheduledStarts)) {
              this.logMessage({ context: 'startup', currentState: 'running', desiredState: 'stopped' });
              callback(true);
            }
            else {
              this.logMessage({ context: 'startup', currentState: 'running', desiredState: 'running' });
              callback(false);
            }
          }
          else {
            this.logMessage({ context: 'startup', currentState: 'stopped', desiredState: 'stopped'
            })
            callback(false);
          }
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);   
    }
  };

  this.toStart = (callback) => {
    try {
      resource.isStopped((stopped, error) => {
        if(error) {
          callback(false);
        }
        else {
          if(stopped) {
            if(this.scheduledStarts.lastMoreRecentThan(this.scheduledStops)) {
              this.logMessage({ context: 'shutdown', currentState: 'stopped', desiredState: 'running' });
              callback(true);
            }
            else {
              this.logMessage({ context: 'shutdown', currentState: 'stopped', desiredState: 'stopped' });
              callback(false);
            }
          }
          else {
            this.logMessage({ context: 'shutdown', currentState: 'running', desiredState: 'running' });
            callback(false);
          }
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);
    }
  };

  
  this.toReboot = (callback) => {
    try {
      resource.isRunning((running, error) => {
        let reboot = false;
        if( ! error) {

          // Load up the reboot schedule hierarchy
          let hierarchy = new RebootScheduleHierarchy(this.scheduledRebootsArray, resource, running);

          // Get those items that indicate the reboot action to take with accompanying messages to log
          let rebootNowData = hierarchy.getRebootNowData();
          let rebootNextData = hierarchy.getNextRebootData();
          if(rebootNowData.rebootNow) {
            reboot = true;
            console.log(rebootNowData.message);
          }
          else if (rebootNextData) {
            console.log(rebootNextData.message);
          }
          else {
            callback(false);
            return;
          }

          // Find out if the next reboot time has changed from its last recorded value (tagged on the resource).
          let nextRebootTagKey = 'NextScheduledReboot';
          if(rebootNextData && rebootNextData.nextRebootDateString) {
            let existingTagValue = this.resource.basicResource.getTagValue(nextRebootTagKey);
            if(rebootNextData.nextRebootDateString != existingTagValue) {
              // Let the resource display in a tag when the next time it is scheduled to reboot occurs.
              this.resource.basicResource.applyTag(
                AWS, 
                () => {
                  callback(reboot);
                }, 
                nextRebootTagKey, 
                rebootNextData.nextRebootDateString
              );
              return;
            }
          } 
          
          callback(reboot);
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);
    }
  };
};

function RebootScheduleHierarchy(scheduledRebootsArray, resource, running) {

  this.members = [];

  this.initialize = () => {
    scheduledRebootsArray.forEach((scheduledReboot) => {
      this.add(scheduledReboot, resource, running);
    });
  }

  this.add = (rebootCron, resource, running) => {

    let reboot = false;
    let rid = `${resource.getId()}`;

    if(rebootCron.empty) {
      var decision = 'No reboot'
      if(running) {
        var reason = `${rid} is running but has no reboot schedule`;      
      }
      else {
        var reason = `${rid} is not running and has no reboot schedule`;
      }
    }
    else {
      let lastRecordedReboot = resource.getLastRebootTime();
      let lastSchedString = `${rebootCron.description('reboot')}`;
      let lastRebootString = resource.getLastRebootTimeString();
      if( ! lastRebootString || rebootCron.lastMoreRecentThanDate(lastRecordedReboot)) {
        if(running) {
          /**
           * At this point, the resource is technically scheduled for reboot. However, if the resource was in a stopped
           * state for some reason and missed that last reboot, anyone starting it will find it immediately gets rebooted 
           * once having reached a running state. This would be superfluous and confusing, so the window of time this scenario
           * can occur in is reduced down to one hour, after which, scheduled reboots are ignored until the next hour window opens. 
           */
          if(rebootCron.lastUnderAnHourOld()) {
            var decision = `Resource ${rid} is running and should be rebooted`;
            var reason = `${lastSchedString} is more recent than the last recorded reboot time: ${lastRebootString}`;
            reboot = true;
          }
          else {
            var decision = `Resource ${rid} is running and should not be rebooted`;
            var reason = `${lastSchedString} is more recent than the last recorded reboot time: ${lastRebootString}, but ${rid} missed its 1 hour reboot window`;
          }
        }
        else {
          var decision = `${rid} is scheduled/overdue for reboot, but do not reboot`;
          var reason = `The last recorded reboot time: ${lastRebootString}, is more recent than ${lastSchedString}, but the resource is not running`;
        }
      }
      else {
        var decision = 'No reboot.'
        if(running) {
          var reason = `${rid} is running since last reboot of ${lastRebootString} but is not scheduled for another reboot until ${rebootCron.nextToLocalTimeString()}`;
        }
        else {
          var reason = `${rid} is NOT running and would not be scheduled for reboot until ${rebootCron.nextToLocalTimeString()} (last reboot ${lastRebootString})`;
        }
      }
    } 
    
    this.members.push({
      message: `Reboot decision: ${decision} - Reason: ${reason}`,
      rebootNow: reboot,
      prevRebootDate: rebootCron.prevDate(),
      nextRebootDate: rebootCron.nextDate(),
      nextRebootDateString: rebootCron.nextToLocalTimeString()
    });
  };

  this.getRebootNowData = () => {
    let selectedMember = this.members.reduce((lastMember, member) => {
      if(lastMember && lastMember.rebootNow) {
        if(member.rebootNow) {
          // Return the earliest of the two prior overdue reboots
          return lastMember.prevRebootDate < member.prevRebootDate ? lastMember : member;
        }
      }
      if(member.rebootNow) {
        return member;
      }
    });
    if(selectedMember) {
      return selectedMember;
    }
    else {
      return this.getLastRebootData();
    }
  };

  this.getLastRebootData = () => {
    let selectedMember = this.members.reduce((lastMember, member) => {
      if(lastMember) {
        // Return the latest of the two prior scheduled reboots
        return lastMember.prevRebootDate < member.prevRebootDate ? member : lastMember;
      }
      return member
    });
    return selectedMember;
  };

  this.getNextRebootData = () => {
    let selectedMember = this.members.reduce((lastMember, member) => {
      if(lastMember) {
        // Return the earliest of the two future scheduled reboots
        return lastMember.nextRebootDate < member.nextRebootDate ? lastMember : member;
      }
      return member
    });
    return selectedMember;
  };

  this.initialize();
}