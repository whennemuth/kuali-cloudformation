
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

  this.getArn = () => {
    return this.tagsAndArn.ResourceARN;
  }

  this.getTagValue = (key) => {
    tags = this.tagsAndArn.Tags;
    for(var i=0; i<tags.length; i++) {
      if(key.equalsIgnoreCase(tags[i].Key)) {
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

  this.getStartCron = () => {
    return this.getTagValue(this.tagsOfInterest.cron.start);
  }

  this.getStopCron = () => {
    return this.getTagValue(this.tagsOfInterest.cron.stop);
  }

  this.getState = () => {
    return this.state;
  }
  this.setState = (state) => {
    this.state = state;
  }
};
