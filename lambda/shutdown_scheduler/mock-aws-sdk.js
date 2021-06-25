
const delay = .2;

const MOCK_IDS = {
  ec2: {
    mock1: {
      id: 'i-08eac5cd2d59b1fdb',
      state: 'running'
    },
    mock2: {
      id: 'i-0258a5f2a87ba7972',
      state: 'stopped'
    },
    mock3: {
      id: 'i-099de1c5407493f9b',
      state: 'pending'
    }
  },
  rds: {
    mock1: {
      id: 'kuali-oracle-stg',
      state: 'available'
    }
  }
};

var mockdata = new (function(ids) {
  this.ids = ids;
  this.get = (type, id) => {
    if(Number.isInteger(id)) {
      return this.ids[type][`mock${id}`];
    }
    for(var i=1; ; i++) {
      if (Object.hasOwnProperty.call(this.ids[type], `mock${i}`)) {
        if(this.ids[type][`mock${i}`].id == id) {
          return this.ids[type][`mock${i}`];
        }          
      }
      else {
        break;
      }
    }
    throw new Error("Invalid mock query!");
  }
  this.getEC2 = (id) => { return this.get('ec2', id); }
  this.getRDS = (id) => { return this.get('rds', id); }
})(MOCK_IDS);


module.exports = {
  ResourceGroupsTaggingAPI: function() {
    this.counter = 1,
    this.tokens = [ "token1", "token2", "token3" ],
    this.getResources = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          PaginationToken: "",
          ResourceTagMappingList: [
            {
              ResourceARN: `arn:aws:rds:us-east-1:770203350335:db:${mockdata.getRDS(1).id}`,
              Tags: [
                { Key: "App", Value: "Kuali" },
                { Key: "Function", Value: "kuali" },
                { Key: "Category", Value: "database" },
                { Key: "Landscape", Value: "stg" },
                { Key: "Subcategory", Value: "oracle" },
                { Key: "Version", Value: "1" },
                { Key: "Service", Value: "research-administration" },
                { Key: "Baseline", Value: "stg" },
                { Key: "Name", Value: mockdata.getEC2(1).id },
                { Key: "StartupCron", Value: "0 10 ? * MON-FRI" },
                { Key: "ShutdownCron", Value: "15 0 ? * MON-FRI" },
                { Key: "LocalTimeZone", Value: "America/New_York" }
              ]
            },
            {
              ResourceARN: `arn:aws:ec2:us-east-1:770203350335:instance/${mockdata.getEC2(1).id}`,
              Tags: [
                { Key: "Function", Value: "kuali" },
                { Key: "Service", Value: "research-administration" },
                { Key: "aws:cloudformation:logical-id", Value: "EC2Instance" },
                { Key: "ShortName", Value: "jenkins" },
                { Key: "Name", Value: "kuali-jenkins" },
                { Key: "StartupCron", Value: "15 10 ? * MON-FRI" },
                { Key: "ShutdownCron", Value: "0 0 ? * MON-FRI" },
                { Key: "LocalTimeZone", Value: "America/New_York" }
              ]
            },
            {
              ResourceARN: `arn:aws:ec2:us-east-1:770203350335:instance/${mockdata.getEC2(2).id}`,
              Tags: [
                { Key: "Function", Key: "kuali" },
                { Key: "Service", Key: "research-administration" },
                { Key: "aws:cloudformation:logical-id", Key: "EC2Instance" },
                { Key: "ShortName", Key: "ci" },
                { Key: "Name", Key: "buaws-kuali-app-ci001" },
                { Key: "StartupCron", Value: "15 10 ? * MON-FRI" },
                { Key: "ShutdownCron", Value: "0 0 ? * MON-FRI" },
                { Key: "LocalTimeZone", Value: "America/New_York" }
              ]
            },
            {
              ResourceARN: `arn:aws:ec2:us-east-1:770203350335:instance/${mockdata.getEC2(3).id}`,
              Tags: [
                { Key: "Function", Key: "kuali" },
                { Key: "Service", Key: "research-administration" },
                { Key: "aws:cloudformation:logical-id", Key: "EC2Instance" },
                { Key: "ShortName", Key: "sb" },
                { Key: "Name", Key: "buaws-kuali-app-sb001" },
                { Key: "LocalTimeZone", Value: "America/New_York" }
              ]
            }
          ]          
        });
      }, delay * 1000);
    }
  },

  EC2: function() {
    this.describeInstanceStatus = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          InstanceStatuses: [
            {
              InstanceState: {
                Name: mockdata.getEC2(params.InstanceIds[0]).state
              }, 
            }
          ]
        });
      }, delay * 1000);
    }

    this.changeInstances = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          // Combining mocked reply data that would be present for both stop and start. A real reply would only have one or the other.
          StartingInstances: [{
            InstanceId: params.InstanceIds[0]
          }],
          StoppingInstances: [{
            InstanceId: params.InstanceIds[0]
          }]
        });
      }, delay * 1000);
    }

    this.startInstances = (params, callback) => {
      this.changeInstances(params, callback);
    }

    this.stopInstances = (params, callback) => {
      this.changeInstances(params, callback);
    }
  },

  RDS: function() {
    this.describeDBInstances = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          DBInstances: [{
            DBInstanceStatus: mockdata.getRDS(params.DBInstanceIdentifier).state
         }]
        });
      }, delay * 1000);
    }

    this.changeDBInstance = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          DBInstance: {
            DBInstanceIdentifier: params.DBInstanceIdentifier
          }
        });
      }, delay * 1000);
    }

    this.startDBInstance = (params, callback) => {
      this.changeDBInstance(params, callback);
    }

    this.stopDBInstance = (params, callback) => {
      this.changeDBInstance(params, callback);
    }
  }
};
