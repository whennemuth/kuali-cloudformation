
module.exports = function(AWS, sgId) {
  
  const ec2 = new AWS.EC2();

  this.members = [];

  this.getAll = () => { return members; }

  this.each = action => {
    this.members.forEach(member => {
      action(member);
    });
  };

  return new Promise (
    (resolve) => {
      try {
        resolve((async () => {
          await ec2.describeSecurityGroups({ VpcId: vpcId }).promise()
            .then(data => {
              data.StaleSecurityGroupSet.forEach(sg => {
                if(filter.qualifies(sg)) {
                  members.push(sg);
                }
              });          
            })
            .catch(err => {
              throw(err);
            })
          return this;
        })());
      }
      catch(err) {
        throw(err);
      }      
    }
  );
}
