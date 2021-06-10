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

  this.getState = (callback) => {
    if(this.basicResource.getState()) {
      callback(this.basicResource.getState());
    }
    else {
      var id = this.getId();
      if(id) {
        var ec2 = new AWS.EC2();
        var self = this;
        ec2.describeInstanceStatus({ InstanceIds: [ id ]}, function(err, data) {
          try {
            if (err) {
              throw err;
            }
            else {
              // console.log(JSON.stringify(data, null, 2));
              var state = data.InstanceStatuses[0].InstanceState.Name;
              self.basicResource.setState(state);
              callback(state);
            }          
          } 
          catch (e) {
            e.stack ? console.error(e, e.stack) : console.error(e);
            callback(e.name)
          }
        });      
      }
      else {
        console.log("ERROR! Cannot determine ec2 instanceId!");
        callback('');
      }
    }
  }

  this.isRunning = (callback) => {
    return this.getState((state) => {
      callback(state.equalsIgnoreCase('RUNNING'));
    });
  }

  this.isStopped = (callback) => {
    return this.getState((state) => {
      callback(state.equalsIgnoreCase('STOPPED'));
    });
  }
  
  this.change = (ec2Method, callback) => {
    ec2Method({ InstanceIds: [ this.getId() ] }, function(err, data) {
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
    console.log(`Starting ec2 instance ${this.getId()}...`);
    var ec2 = new AWS.EC2();
    this.change(ec2.startInstances, callback);
  }

  this.stop = (callback) => {
    console.log(`Stopping ec2 instance ${this.getId()}...`);
    var ec2 = new AWS.EC2();
    this.change(ec2.stopInstances, callback);
  }
}