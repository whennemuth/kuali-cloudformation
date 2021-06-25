const parser = require('cron-parser');

/**
 * This module wraps the cron-parser library as a facade/adapter with utility methods to make client code shorter
 * and provide language to provide a little more ease of use and specificity to the context. 
 * 
 * @param {*} cronExpression 
 * @param {*} timezone 
 * @param {*} awsCron 
 */
module.exports = function(cronExpression, timezone, awsCron) {

  this.prev = () => {
    return this.prevTime;
  }

  this.next = () => {
    return this.nextTime;
  }

  this.prevDate = () => {
    if(this.prevTime) {
      return this.prevTime.toDate();
    }
    return null;
  }

  this.nextDate = () => {
    if(this.nextTime) {
      return this.nextTime.toDate();
    }
    return null;
  }

  this.lastMoreRecentThan = (otherCronObj) => {
    if(this.prevTime && !otherCronObj.prev()) {
      return true;
    }
    else if(otherCronObj.prev() && this.prevTime) {
      return this.prevTime.toDate() > otherCronObj.prev().toDate();
    }
    else {
      return false;
    }
  }

  this.lastMoreRecentThanDate = (d) => {
    if(d instanceof Date) {
      if(this.prevTime) {
        return this.prevTime.toDate() > d;
      }
    }
    return false;
  }

  this.lastUnderAnHourOld = () => {
    let hour = 1000 * 60 * 60;
    let hourAgo = new Date(Date.now() - hour);
    return this.lastMoreRecentThanDate(hourAgo);
  }

  this.toLocalTime = (d) => {
    return new Date(this.toLocalTimeString(d));
  }

  this.toLocalTimeString = (d) => {
    if(d) {
      return d.toLocaleString("en-US", {
        timeZone: timezone
      });
    }
    return null;
  }

  this.lastToLocalTimeString = () => {
    if(this.prevTime) {
      let prevdate = this.prevTime.toDate();
      return this.toLocalTimeString(prevdate);
    }
    return '';
  }

  this.nextToLocalTimeString = () => {
    if(this.nextTime) {
      let nextdate = this.nextTime.toDate();
      return this.toLocalTimeString(nextdate);
    }
    return '';
  }

  this.getLocalNowString = () => {
    return this.toLocalTimeString(new Date());
  }

  this.description = (type) => {
    return `The last scheduled ${type} time ${this.lastToLocalTimeString()}`;
  }

  /**
   * Instantiate for a regular cron expression.
   * SEE: https://www.npmjs.com/package/cron-parser
   * 
   * @param {*} cronExpr 
   */
  this.instantiateBasicCron = (cronExpr) => {
    this.cronExpression = cronExpr;
    let parsed = parser.parseExpression(cronExpr, {
      tz: timezone
    });
    this.prevTime = parsed.prev();
    if(this.prevTime.toDate() > new Date()) {
      this.prevTime = parsed.prev();
    }
    this.nextTime = parsed.next();
    if(this.nextTime.toDate() < new Date()) {
      this.nextTime = parsed.next();
    }
  }

  /**
   * Instantiate for an aws cron expression, which does not have seconds, but does have a year.
   * To be parseable a placeholder for the seconds have to be added and the year lopped off.
   * SEE: https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
   * 
   * @param {*} cronExpr 
   */
  this.instantiateAwsCron = (cronExpr) => {
    this.awsCronExpression = cronExpr;
    let parts = cronExpr.split(/\s+/);
    if(parts.length === 6) {      
      parts.pop(); //Remove year      
      parts.unshift('0'); // Add seconds
      this.instantiateBasicCron(parts.join(" "));
    }
    else {
      throw new Error(`Bad cron expression (${cronExpression}): 6 fields required.`);
    }
  }

  this.isEmpty = () => {
    return this.empty;
  }
  
  if(cronExpression) {
    if(awsCron) {
      this.instantiateAwsCron(cronExpression);
    }
    else {
      this.instantiateBasicCron(cronExpression);
    }
  }
  else {
    this.empty = true;
  }
}
