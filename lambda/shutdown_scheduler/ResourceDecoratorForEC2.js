module.exports = function(basicResource, AWS) {
  this.AWS = AWS;
  this.basicResource = basicResource;
  this.basicResource.autoDecorate(this);
  
  this.getId = () => {
    if(this.getArn()) {
      return this.getArn().split("/")[1];
    }
    return this.getName();
  }

  this.getIntroduction = () => {
    return basicResource.getIntroduction(this.getId());
  }

  /**
   * Decorate the getState method with api call specific to acquiring the state of an ec2 instance.
   * @param {*} callback 
   */
  this.getState = (callback) => {
    if(this.basicResource.getState()) {
      callback(this.basicResource.getState());
    }
    else {
      var id = this.getId();
      if(id) {
        var ec2 = new AWS.EC2();
        var self = this;
        ec2.describeInstanceStatus({ InstanceIds: [ id ], IncludeAllInstances: true}, function(err, data) {
          try {
            if (err) {
              console.error(`Cannot determine state of ${self.getId()}`);
              throw err;
            }
            else {
              var state = data.InstanceStatuses[0].InstanceState.Name;
              self.basicResource.setState(state);
              // console.log(`State of ${self.getId()} is ${state}`);
              callback(state);
            }          
          } 
          catch (e) {
            console.error(`Cannot establish state of ${self.getId()}`);
            e.stack ? console.error(e, e.stack) : console.error(e);
            callback(e.name, true);
          }
        });      
      }
      else {
        console.error("ERROR! Cannot determine ec2 instanceId!");
        callback('', true);
      }
    }
  }

  this.isRunning = (callback) => {
    return this.getState((state, error) => {
      callback(state.equalsIgnoreCase('RUNNING'), error);
    });
  }

  this.isStopped = (callback) => {
    return this.getState((state, error) => {
      callback(state.equalsIgnoreCase('STOPPED'), error);
    });
  }

  this.start = (callback) => {
    this.basicResource.logHeading(`STARTING EC2 INSTANCE ${this.getId()}...`);
    var ec2 = new AWS.EC2();
    ec2.startInstances({ InstanceIds: [ this.getId() ] }, function(err, data) {
      if (err) {
        console.error(err, err.stack);
        callback(e.name)
      }
      else {
        callback();
      }
    });
  }

  this.stop = (callback) => {
    this.basicResource.logHeading(`STOPPING EC2 INSTANCE ${this.getId()}...`);
    var ec2 = new AWS.EC2();
    ec2.stopInstances({ InstanceIds: [ this.getId() ] }, function(err, data) {
      if (err) {
        console.error(err, err.stack);
        callback(e.name)
      }
      else {
        callback();
      }
    });
  }

  this.reboot = (callback) => {
    this.basicResource.logHeading(`REBOOTING EC2 INSTANCE ${this.getId()}...`);
    var ec2 = new AWS.EC2();
    var self = this;
    ec2.rebootInstances({ InstanceIds: [ this.getId() ] }, function(err, data) {
      if (err) {
        console.error(err, err.stack);
        callback(e.name);
      }
      else {
        console.log(`Reboot command issued. Proceeding to update ${self.basicResource.tagsOfInterest.lastRebootTag} tag value...`);
        self.basicResource.tagWithLastRebootTime(AWS, callback);        
      }
    });
  }
}