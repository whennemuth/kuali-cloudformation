module.exports = function(basicResource, AWS) {
  this.AWS = AWS;
  this.basicResource = basicResource;
  this.basicResource.autoDecorate(this);
  
  this.getId = () => {
    if(this.getArn()) {
      return this.getArn().split(":").pop();      
    }
    return this.getName();
  }

  this.getIntroduction = () => {
    return basicResource.getIntroduction(this.getId());
  }
  
  /**
   * Decorate the getState method with api call specific to acquiring the state of an rds instance.
   * @param {*} callback 
   */
   this.getState = (callback) => {
    if(this.basicResource.getState()) {
      callback(this.basicResource.getState());
    }
    else {
      var id = this.getId();
      if(id) {
        var rds = new AWS.RDS();
        var self = this;
        rds.describeDBInstances({ DBInstanceIdentifier: id}, function(err, data) {
          try {
            if (err) {
              console.error(`Cannot establish state of ${self.getId()}`);
              throw err;
            }
            else {
              var state = data.DBInstances [0].DBInstanceStatus;
              self.basicResource.setState(state);
              console.log(`State of ${self.getId()} is ${state}`);
              callback(state);
            }
          }
          catch(e) {
            console.error(`Cannot establish state of ${self.getId()}`);
            e.stack ? console.error(e, e.stack) : console.error(e);
            callback(e.name, true)
          }
        });      
      }
      else {
        console.log("ERROR! Cannot determine rds instanceId!");
        callback('', true);
      }
    }
  };

  this.isRunning = (callback) => {
    return this.getState((state, error) => {
      callback(state.equalsIgnoreCase('AVAILABLE'), error);
    });
  }

  this.isStopped = (callback) => {
    return this.getState((state, error) => {
      callback(state.equalsIgnoreCase('STOPPED'), error);
    });
  }

  this.start = (callback) => {
    this.basicResource.logHeading(`STARTING RDS INSTANCE ${this.getId()}...`);
    var rds = new AWS.RDS();
    rds.startDBInstance({ DBInstanceIdentifier: this.getId()}, function(err, data) {
      if (err) {
        console.log(err, err.stack);
        callback(e.name)
      }
      else {
        callback();
      }
    });
  }

  this.stop = (callback) => {
    this.basicResource.logHeading(`STOPPING RDS INSTANCE ${this.getId()}...`);
    var rds = new AWS.RDS();
    rds.stopDBInstance({ DBInstanceIdentifier: this.getId()}, function(err, data) {
      if (err) {
        console.log(err, err.stack);
        callback(e.name)
      }
      else {
        callback();
      }
    });
  }

  this.reboot = (callback) => {
    this.basicResource.logHeading(`REBOOTING RDS INSTANCE ${this.getId()}...`);
    var rds = new AWS.RDS();
    var self = this;
    rds.rebootDBInstance({ DBInstanceIdentifier: this.getId()}, function(err, data) {
      if (err) {
        console.log(err, err.stack);
        callback(e.name)
      }
      else {
        self.basicResource.tagWithLastRebootTime(AWS, callback);
      }
    });
  }
}