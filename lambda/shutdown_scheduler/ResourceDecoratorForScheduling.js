
const parser = require('cron-parser');

/**
 * An aws cron expression does not have seconds, but does have a year.
 * To be parseable a placeholder for the seconds have to be added and the year lopped off.
 * SEE: https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
 */
const AWSCron = function(expression) {
  let parts = expression.split(/\s+/);
  if(parts.length === 6) {
    //Remove year
    parts.pop();
    // Add seconds
    parts.unshift('0');
    let parseable = parts.join(" ");
    this.parsed = parser.parseExpression(parseable);
  }
  else {
    throw new Error(`Bad cron expression (${expression}): 6 fields required.`);
  }

  this.prev = () => {
    return this.parsed.prev();
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
    this.lastStart = new AWSCron(resource.getStartCron()).prev();
    this.lastStop = new AWSCron(resource.getStopCron()).prev();
    // this.startMsg = `the most recent scheduled start time ${this.lastStart.toISOString()}`
    // this.stopMsg = `the most recent scheduled stop time ${this.lastStop.toISOString()}`
    let started = this.lastStart.toDate();
    let stopped = this.lastStop.toDate();
    started.setTime(started.getTime() - started.getTimezoneOffset()*60*1000);
    stopped.setTime(stopped.getTime() - stopped.getTimezoneOffset()*60*1000);
    this.startMsg = `The last scheduled start time ${started.toLocaleString("en-US")}`
    this.stopMsg = `The last scheduled stop time ${stopped.toLocaleString("en-US")}`
    this.resource = resource;
  }
  catch(e) {
    this.handleError(e);
  }

  this.toStop = (callback) => {
    try {
      resource.isRunning((running) => {
        if(running) {
          if(this.lastStop > this.lastStart) {
            console.log(`Resource ${this.resource.getId()} should be stopped:\n   ${this.stopMsg} is more recent than ${this.startMsg}`);
            callback(true);
          }
          else {
            console.log(`Resource ${this.resource.getId()} should not be stopped:\n   ${this.startMsg} is more recent than ${this.stopMsg}`);
            callback(false);
          }
        }
        else {
          console.log(`Resource ${this.resource.getId()} is already stopped.`)
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
          if(this.lastStart > this.lastStop) {
            console.log(`Resource ${this.resource.getId()} should be started:\n   ${this.startMsg} is more recent than ${this.stopMsg}`);
            callback(true);
          }
          else {
            console.log(`Resource ${this.resource.getId()} should not be started:\n   ${this.stopMsg} is more recent than ${this.startMsg}`);
            callback(false);
          }
        }
        else {
          console.log(`Resource ${this.resource.getId()} is already running.`)
          callback(false);
        }
      });
    }
    catch(e) {
      this.handleError(e, callback);
    }
  }
};