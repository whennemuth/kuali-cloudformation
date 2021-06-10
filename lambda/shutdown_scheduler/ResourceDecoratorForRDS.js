module.exports = function(basicResource, AWS) {
  this.basicResource = basicResource;
  this.AWS = AWS;
  
  this.getId = () => {
    if(this.basicResource.getArn()) {
      return this.basicResource.getArn().split(":").pop();      
    }
    return "";
  }

  this.getStartCron = () => {
    return this.basicResource.getStartCron();
  }

  this.getStopCron = () => {
    return this.basicResource.getStopCron();
  }
  
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
              throw err;
            }
            else {
              // console.log(JSON.stringify(data, null, 2));
              var state = data.DBInstances [0].DBInstanceStatus;
              self.basicResource.setState(state);
              callback(state);
            }
          }
          catch(e) {
            e.stack ? console.error(e, e.stack) : console.error(e);
            callback(e.name)
          }
        });      
      }
      else {
        console.log("ERROR! Cannot determine rds instanceId!");
        callback('');
      }
    }
  };

  this.isRunning = (callback) => {
    return this.getState((state) => {
      callback(state.equalsIgnoreCase('AVAILABLE'));
    });
  }

  this.isStopped = (callback) => {
    return this.getState((state) => {
      callback(state.equalsIgnoreCase('STOPPED'));
    });
  }
  
  this.change = (rdsMethod, callback) => {
    rdsMethod({ DBInstanceIdentifier: this.getId()}, function(err, data) {
      if (err) {
        console.log(err, err.stack);
        callback(e.name)
      }
      else {
        // console.log(data);
        callback();
      }
    });
  }

  this.start = (callback) => {
    console.log(`Starting rds instance ${this.getId()}...`);
    var rds = new AWS.RDS();
    this.change(rds.startDBInstance, callback);
  }

  this.stop = (callback) => {
    console.log(`Stopping rds instance ${this.getId()}...`);
    var rds = new AWS.RDS();
    this.change(rds.stopDBInstance, callback);
  }
}