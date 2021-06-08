const LAST_DESIRED_COUNT_TAG = 'LastDesiredCount';

module.exports = function(basicResource, AWS) {
  this.basicResource = basicResource;
  this.AWS = AWS;

  this.getId = () => {
    if(this.basicResource.getArn()) {
      return this.basicResource.getArn().split("/")[1];
    }
    return "";
  }

  this.getStartCron = () => {
    return this.basicResource.getStartCron();
  }

  this.getStopCron = () => {
    return this.basicResource.getStopCron();
  }
  
  this.getDesiredCount = (callback) => {
    var desiredCount = "TODO: Set this in a callback"
    callback(desiredCount);
  };

  this.setDesiredCountTag = (desiredCount, callback) => {
    console.log(`Setting desiredCount tag to ${desiredCount}`)
    callback(desiredCount)
  }

  this.isRunning = (callback) => {
    return this.getDesiredCount((state) => {
      callback(state.equalsIgnoreCase('RUNNING'));
    });
  }

  this.isStopped = (callback) => {
    return this.getDesiredCount((desiredCount) => {
      callback(desiredCount == 0);
    });
  }

  this.stop = (callback) => {
    console.log("Scaling down ecs cluster to zero...");
    this.getDesiredCount(() => {
      this.setDesiredCountTag(lastDesiredCount, () => {
        console.log('Setting desiredCount to zero');
        callback();
      })
    });
  }
  
  this.start = (callback) => {
    var lastDesiredCount = this.basicResource.getTagValue(LAST_DESIRED_COUNT_TAG);
    console.log("Scaling up ecs cluster to...");
    callback();
  }

}