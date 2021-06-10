
const parser = require('cron-parser');

/**
 * An aws cron expression does not have seconds, but does have a year.
 * To be parseable a placeholder for the seconds have to be added and the year lopped off.
 * SEE: https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
 */
const AWSCron = function(cronExpression) {
  if(cronExpression) {
    let parts = cronExpression.split(/\s+/);
    if(parts.length === 6) {
      //Remove year
      parts.pop();
      // Add seconds
      parts.unshift('0');
      let parseable = parts.join(" ");
      this.parsed = parser.parseExpression(parseable);
      this.prevTime = this.parsed.prev();
    }
    else {
      throw new Error(`Bad cron expression (${cronExpression}): 6 fields required.`);
    }
  }
  this.prev = () => {
    return this.prevTime;
  }
  this.moreRecentThan = (awscron) => {
    if(this.prevTime && !awscron.prev()) {
      return true;
    }
    else if(awscron.prev() && !this.prevTime) {
      return false;
    }
    else {
      this.prevTime > awscron.prev();
    }    
  }
  this.toLocalTime = () => {
    if(this.prevTime) {
      var prevdate = this.prevTime.toDate();
      prevdate.setTime(prevdate.getTime() - prevdate.getTimezoneOffset()*60*1000);
      return prevdate.toLocaleString("en-US");
    }
    return "none";
  }
  this.description = (type) => {
    return `The last scheduled ${type} time ${this.toLocalTime()}`;
  }
}

module.exports = function(resource) {

  this.handleError = (e, callback) => {
    e.stack ? console.error(e, e.stack) : console.error(e);
    this.error = true;
    if(callback) {
      callback(false);   
    }
  }

  try {
    // var startcron = resource.getStartCron();
    // var stopcron = resource.getStopCron();
    // this.lastStart = new AWSCron(startcron).prev();
    // this.lastStop = new AWSCron(stopcron).prev();
    // let started = this.lastStart.toDate();
    // let stopped = this.lastStop.toDate();
    // started.setTime(started.getTime() - started.getTimezoneOffset()*60*1000);
    // stopped.setTime(stopped.getTime() - stopped.getTimezoneOffset()*60*1000);

    this.lastStart = new AWSCron(resource.getStartCron());
    this.lastStop = new AWSCron(resource.getStopCron());
    this.resource = resource;
  }
  catch(e) {
    this.handleError(e);
  }

  this.logMessage = (parms) => {
    var action = parms.desiredState === 'running' ? 'Start' : 'Stop';
    if(parms.currentState == parms.desiredState) {
      if((parms.context === 'startup' && parms.desiredState === 'running') || (parms.context === 'shutdown' && parms.desiredState === 'stopped')) {
        var decision = `Leave ${this.resource.getId()} alone.`;
        var reason = `Resource ${this.resource.getId()} is already ${parms.desiredState}.`;
        console.log(`${action} decision: ${decision}\nReason: ${reason}`);
        return;
      }
      else {
        var decision = `Resource ${this.resource.getId()} is ${parms.currentState} and should remain that way`;
      }
    }
    else {
      var decision = `Resource ${this.resource.getId()} is ${parms.currentState} and should be ${parms.desiredState}.`;
    }

    if( ! this.lastStop.prev()) {
      var reason = `${this.lastStart.description('start')} has no future stop time.`
    }
    else if( ! this.lastStart.prev()) {
      var reason = `${this.lastStop.description('stop')} has no future start time.`
    }
    else if(parms.currentState === 'running') {
      var reason = `${this.lastStop.description('stop')} is more recent than ${this.lastStart.description('start')}`;
    }
    else {
      var reason = `${this.lastStart.description('start')} is more recent than ${this.lastStop.description('stop')}`;
    }
    console.log(`${action} decision: ${decision}\nReason: ${reason}`);
  }

  this.toStop = (callback) => {
    try {
      resource.isRunning((running) => {
        if(running) {
          if(this.lastStop.moreRecentThan(this.lastStart)) {
            this.logMessage({
              context: 'startup',
              currentState: 'running',
              desiredState: 'stopped'
            });
            callback(true);
          }
          else {
            this.logMessage({
              context: 'startup',
              currentState: 'running',
              desiredState: 'running'
            });
            callback(false);
          }
        }
        else {
          this.logMessage({
            context: 'startup',
            currentState: 'stopped',
            desiredState: 'stopped'
          })
          callback(false);
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);   
    }
  }

  this.toStart = (callback) => {
    try {
      resource.isStopped((stopped) => {
        if(stopped) {
          if(this.lastStart.moreRecentThan(this.lastStop)) {
            this.logMessage({
              context: 'shutdown',
              currentState: 'stopped',
              desiredState: 'running'
            });
            callback(true);
          }
          else {
            this.logMessage({
              context: 'shutdown',
              currentState: 'stopped',
              desiredState: 'stopped'
            });
            callback(false);
          }
        }
        else {
          this.logMessage({
            context: 'shutdown',
            currentState: 'running',
            desiredState: 'running'
          });
          callback(false);
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);
    }
  }
};