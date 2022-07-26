
const Stack = function(stackSummary, rdsVpcSecGrpParmName) {
  this.summary = JSON.stringify(stackSummary, null, 2);
  this.details = null;
  this.detailsString = null;
  this.loadDetails = async cloudformation => {
    return new Promise(
      (resolve) => {
        try {
          resolve((async () =>{
            await cloudformation.describeStacks({StackName: stackSummary.StackId}).promise()
              .then(data => {
                this.details = data.Stacks[0];
                this.detailsString = JSON.stringify(this.details, null, 2);
              })
              .catch(err => {
                throw(err);
              });
            return this.details;      
          })());
        }
        catch (err) {
          throw(err);
        }
      }  
    );
  }
  this.updateRdsVpcSecurityGroupId = async (AWS, sgId) => {
    return new Promise(
      (resolve) => {
        try {

          // Recreate the stack parameter list with all the same parameters EXCEPT rdsVpcSecGrpParmName
          var stackparms = [];
          stackparms = this.details.Parameters.reduce((prev, curr) => {
            if(curr.ParameterKey == rdsVpcSecGrpParmName) {
              prev.push({
                ParameterKey: curr.ParameterKey,
                ParameterValue: sgId
              })
            }
            else {
              prev.push({
                ParameterKey: curr.ParameterKey,
                UsePreviousValue : true
              })
            }
            return prev;
          }, stackparms)

          resolve((async () => {
            var cloudformation = new AWS.CloudFormation();
            var params = {
              StackName: this.details.StackName,
              UsePreviousTemplate: true,
              Parameters: stackparms,
              Capabilities: [ 'CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM' ]
            };
            var data = null;
            await cloudformation.updateStack(params).promise()
              .then(d => {
                data = d;
              })
              .catch(err => {
                throw(err);
              })
            return data;
          })());
        }
        catch(err) {
          throw(err);
        }
      }
    )
  }
  this.getName = () => {
    return this.details.StackName;
  }
  this.getParameterValue = tagname => {
    var parm = this.details.Parameters.find(parm => {
      return parm.ParameterKey == tagname;
    })
    return parm ? parm.ParameterValue : undefined;
  }
  this.getRdsSecurityGroupId = () => {
    return this.getParameterValue(rdsVpcSecGrpParmName);
  }
  this.securityGroupMismatch = rdsDb => {
    if( ! this.getRdsSecurityGroupId()) {
      return false;
    }
    rdsSecGrps = rdsDb.getVpcSecurityGroups();
    if(rdsSecGrps.length == 0) {
      return false;
    }
    var mismatch = true;
    rdsSecGrps.forEach(sg => {
      if(sg.VpcSecurityGroupId == this.getRdsSecurityGroupId()) {
        mismatch = false;
      }
    });
    return mismatch;
  }
}

const getStacks = function(parms) {
  var rgtAPI = new parms.AWS.ResourceGroupsTaggingAPI();
  var cloudformation = new parms.AWS.CloudFormation();

  return new Promise(
    (resolve) => {
      try {
        resolve((async () => {

          // 1) Get resource info for all stacks that are identified as kuali-research stacks by their tags
          var kualiAppStacks = null;
          await rgtAPI.getResources(parms.ResourceGroupsTaggingApiParms).promise()
            .then(data => {
              kualiAppStacks = data;
            })
            .catch(err => {
              throw(err);
            });

          // 2) From the resource list, get a corresponding list of stack summaries and reduce it down to only root stacks (ignore nested).
          var rootKualiAppStacks = [];
          await cloudformation.listStacks(parms.CloudFormationParms).promise()
            .then(data => {
              data.StackSummaries.forEach(summary => {
                if( ! summary.RootId) {
                  if(kualiAppStacks.ResourceTagMappingList.find(stack => {
                    return summary.StackId == stack.ResourceARN;
                    
                  })) {
                    rootKualiAppStacks.push(new Stack(summary, parms.RdsVpcSecGrpParmName));
                  }                    
                }
              })
            })
            .catch(err => {
              throw(err);
            });

          // 3) Turn each root kuali stack summary into a detailed stack.
          for (const stack in rootKualiAppStacks) {
            await rootKualiAppStacks[stack].loadDetails(cloudformation)
              .then(data => {
                console.log(`Loaded details for ${data.StackName}`);
              })
              .catch(err => {
                throw(err);
              });
          }

          return rootKualiAppStacks;
        })());
      }
      catch(err) {
        throw(err);
      }
    }
  )
}

module.exports = function() {
  this.getStacks = getStacks;
}

