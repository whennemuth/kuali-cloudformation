String.prototype.equalsIgnoreCase = function(s) {
  if( ! s) {
    return false;
  }
  return this.toUpperCase() === s.toUpperCase();
};

module.exports = function(tagsAndArn, tagsOfInterest) {
  this.tagsAndArn = tagsAndArn;
  this.tagsOfInterest = tagsOfInterest;
  this.state = '';
  this.highlightRow = '##############################################################';

  this.getArn = () => {
    return this.tagsAndArn.ResourceARN;
  }

  this.getName = () => {
    return this.getTagValue('Name');
  }

  this.getIdWithName = (id) => {
    if(this.getName() && id) {
      if(this.getName().equalsIgnoreCase(id)) {
        return id;
      }
      return `${id} (${this.getName()})`;
    }
    else if(this.getName()) {
      return this.getName();
    }
    else if(id) {
      return id;
    }
    else {
      return 'Unknown!'
    }
  }
 
  this.getIntroduction = (id) => {
    const Cron = require('./CronUtils');
    let localTime = new Cron(null, this.getTimeZone()).getLocalNowString();
    return `RESOURCE: ${this.getIdWithName(id)}, Timezone: ${this.getTimeZone()} - ${localTime}`;
  }

  this.getTagValue = (key) => {
    tags = this.tagsAndArn.Tags;
    for(var i=0; i<tags.length; i++) {
      if(key && key.equalsIgnoreCase(tags[i].Key)) {
        return tags[i].Value;
      }
    } 
    return "";
  }

  this.getType = () => {
    if(this.tagsAndArn && this.tagsAndArn.ResourceARN) {
      var parts = tagsAndArn.ResourceARN.split(":");
      if(parts.length && parts.length > 2) {
        return parts[2];
      }
    }
    return "";
  }

  this.logHeading = (logentry) => {
    console.log(this.highlightRow);
    console.log(`:     ${logentry}`);
    console.log(this.highlightRow);
  }

  this.getStartCron = () => {
    return this.getTagValue(this.tagsOfInterest.cron.startTag);
  }

  this.getStopCron = () => {
    return this.getTagValue(this.tagsOfInterest.cron.stopTag);
  }

  this.getRebootCron = (idx) => {
    let tagValue;
    if(this.isNumeric(idx)) {
      if(idx == 1) {
        // Indexes of "1" are implicit - it is typically omitted for this key, so check for that first.
        tagValue = this.getTagValue(this.tagsOfInterest.cron.rebootTag);
      }
      if( ! tagValue) {
        tagValue = this.getTagValue(this.tagsOfInterest.cron.rebootTag + idx);
      }
    }
    else {
      tagValue = this.getTagValue(this.tagsOfInterest.cron.rebootTag);
    }
    return tagValue;
  }

  /**
   * Starting with the string output of a date that had the clock "turned back" by the timezone 
   * differential, we are restoring it to a UTC date by instantiating a new date object from this 
   * local date string representation. However, because the date object constructor always assumes 
   * this input is of UTC origin, we must correct for this and "turn forward" the clock again by 
   * adding back the timezone differential.
   * 
   * NOTE: Twice a year there may be the potential for glitches if the last reboot time string
   * was recorded while in daylight savings time and read during standard time or vice versa. 
   */
  this.getUTCRestoredDate = (localDateString) => {
    
    // Get the date for the current system
    let hereDate = new Date();
    hereDate.setMilliseconds(0);

    // Get the date in the timezone tagged on the resource
    let thereDateStr = hereDate.toLocaleString('en-US', {timeZone: this.getTimeZone()});
    let thereDate = new Date(thereDateStr);

    // Get the date in the UTC timezone
    let UTCDateStr = hereDate.toLocaleString('en-US', {timeZone: 'UTC'});
    let UTCDate = new Date(UTCDateStr);

    // Get the GMT offset for the provided date 
    let diff = thereDate.getTime() - UTCDate.getTime();
    let diffHrs = diff /1000 /60 /60;
    diffHrs = diffHrs > 0 ? `+${diffHrs}` : diffHrs+''
    if(diffHrs.length == 2) {
      diffHrs = diffHrs.slice(0, 1) + '0' + diffHrs.slice(1);
    }
    let GMTOffset = `GMT${diffHrs}00`

    // Reapply the offset to the provided date string so it 
    // can be converted to a date accurate for its original timezone.
    return new Date(`${localDateString} ${GMTOffset}`);
  }

  this.getLastRebootTime = () => {
    let lastDateStr = this.getLastRebootTimeString();
    if(lastDateStr) {
      try {
        return this.getUTCRestoredDate(lastDateStr);
      }
      catch(e) {
        console.error(`Bad date string: ${lastDateStr}`);
        return null;
      }
    }
    return null;
  }

  this.getLastRebootTimeString = () => {
    return this.getTagValue(this.tagsOfInterest.lastRebootTag);
  }

  this.getTimeZone = () => {
    return this.getTagValue(this.tagsOfInterest.timezoneTag);
  }

  this.setTimeZone = (tz) => {
    this.tagsAndArn.Tags.push({Key: this.tagsOfInterest.timezoneTag, Value: tz});
  }

  this.getState = () => {
    return this.state;
  }
  this.setState = (state) => {
    this.state = state;
  }

  this.isEmptyObject = ( obj ) =>  {  
    for ( var name in obj ) {
        return false;
    }
    return true;
  }

  this.isNumeric = (i) => {
    if(i == undefined) {
      return false;
    }
    return /^\d+$/.test(i+'');
  }

  this.applyTag = (AWS, callback, key, value) => {
    var resourcegroupstaggingapi = new AWS.ResourceGroupsTaggingAPI({apiVersion: '2017-01-26'});
    var params = {
      ResourceARNList: [ ],
      Tags: { }
    }
    params.ResourceARNList.push(this.getArn());
    params.Tags[key] = value;
    var self = this;
    resourcegroupstaggingapi.tagResources(params, function(err, data) {
      if (err) {
        console.error(`Cannot create/update the ${key} tag!`)
        console.error(err, err.stack);
        callback(err.name);
      }
      else {
        if( ! self.isEmptyObject(data.FailedResourcesMap) ) {
          console.log(JSON.stringify(data, null, 2));        
          callback(new Error("Failed tag update!"));
        }
        else {
          console.log(`${key} tag updated.`);
          callback();
        }
      }
    });        

  }

  this.tagWithLastRebootTime = (AWS, callback) => {
    this.applyTag(
      AWS, 
      callback, 
      this.tagsOfInterest.lastRebootTag, 
      new Date().toLocaleString('en-US', {
        timeZone: this.getTimeZone()
      })
    );
  }

  this.getArn.autoDecorate = true;
  this.getName.autoDecorate = true;
  this.getIdWithName.autoDecorate = true;
  this.getIntroduction.autoDecorate = true;
  this.getStartCron.autoDecorate = true;
  this.getStopCron.autoDecorate = true;
  this.getRebootCron.autoDecorate = true;
  this.getLastRebootTime.autoDecorate = true;
  this.getLastRebootTimeString.autoDecorate = true;
  this.getTimeZone.autoDecorate = true;
  this.setTimeZone.autoDecorate = true;
  /**
   * This method can be called by any function object that seeks to wrap and decorate the main exported function 
   * of this module. When this is done, all methods of the wrapped function will be automatically decorated by 
   * the wrapping function when it is instantiated as a new object. The decorating methods will simply call and 
   * return the results of the methods they decorate. So no actual change in behavior is accomplished, but the 
   * methods become available on the decorating function as if by subclassing. As with subclassing, these auto-applied 
   * decorator functions can be "overriden" by explicitly coding them further on down in the decorating "subclass".
   * @param {*} decorator 
   */
  this.autoDecorate = (decorator) => {
    for (const methodName in this) {
      if (Object.hasOwnProperty.call(this, methodName)) {
        const method = this[methodName];
        if(method.autoDecorate) {
          decorator[methodName] = (arg1, arg2, arg3) => {
            return this[methodName](arg1, arg2, arg3);
          }
        }
      }
    }  
  }
};
