const RdsDb = require('../src/RdsDatabase.js');

/**
 * Mocks the response to an AWS request, which is not itself a promise, 
 * but has a promise method that does return one.
 * @param {*} retval 
 * @returns 
 */
function getAwsResponse(retval) {
  return {
    promise: () => {
      return new Promise(
        (resolve) => {
          try {
            resolve(retval);
          }
          catch (err) {
            throw(err);
          }
        }
      );
    }
  };
}

/**
 * Mocks rds describe-instances function by returning canned data from a file.
 * All other rds functions are removed (no non-read CRUD operations possible).
 * @param {*} mockfile 
 * @returns 
 */
exports.getAwsRdsMock = function(mockfile) {
  return {
    RDS: function() {
      this.describeDBInstances = (params) => {
        var record = require(mockfile); 
        return getAwsResponse({ DBInstances: [ record ] });
      }
    }
  };
}

/**
 * Mocks all S3 CRUD operations, except for reads if canned content is provided (rds instance data).
 * @param {*} rdsDb 
 * @returns 
 */
exports.getAwsS3Mock = function(rdsDb) {
  const unmocked = new (require('aws-sdk')).S3();
  return {      
    S3: function() {
      this.headObject = (params) => {
        if(rdsDb) {
          // As long as there is no error, pass anything that is truthy, which causes true as the return value.
          return getAwsResponse({});
        }
        else {
          return unmocked.headObject(params);
        }
      };
      this.getObject = (params) => {
        if(rdsDb) {
          return getAwsResponse({ Body: JSON.stringify(rdsDb.getData(), null, 2) });
        }
        else {
          return unmocked.getObject(params);
        }
      };
      this.putObject = (params) => {
        return getAwsResponse({ data: "Mock s3 putObject result" });
      };
      this.copyObject = (params) => {
        return getAwsResponse({ data: "Mock s3 copyObject result" });
      };
      this.deleteObject = (params) => {
        return getAwsResponse({ data: "Mock s3 deleteObject result" });
      };
    }
  };
}

/**
 * This mocks all Route53 CRUD operations except for reads.
 * Requires all resources specified in launch configuration args exist in the cloud account.
 */
exports.getAwsRoute53Mock = function() {
  const unmocked = new (require('aws-sdk')).Route53();
  return {
    Route53: function() {
      this.listHostedZones = (params) => {
        return unmocked.listHostedZones(params);
      };
      this.getHostedZone = (params) => {
        return unmocked.getHostedZone(params);
      }
      this.listResourceRecordSets = (params) => {
        return unmocked.listResourceRecordSets(params);
      }
      this.changeResourceRecordSets = (params) => {
        return getAwsResponse({
          ChangeInfo: {
           Comment: "This is a mock change", 
           Id: "/change/C2682N5HXP0BZ4", 
           Status: "PENDING", 
           SubmittedAt: new Date().toISOString()
          }
        });
      }
    }
  }
}

/**
 * Mocks all cloudformation CRUD operations, except for reads.
 * @returns 
 */
exports.getAwsCloudFormationMock = function() {
  const unmocked = new (require('aws-sdk')).CloudFormation();
  return {
    CloudFormation: function() {
      this.listStacks = params => {
        return unmocked.listStacks(params);
      }
      this.describeStacks = params => {
        return unmocked.describeStacks(params);
      }
      this.updateStack = params => {
        return getAwsResponse({
          StackId: `Mock stack ID for ${params.StackName}`
        });
      }
    }
  }
}

/**
 * All crud operations are unmocked except for the RDS service, which returns canned describe-instances data from a file.
 * This lets you "pretend" a new rds database has been created, with all real triggered activity that goes with it.
 * @param {*} rdsMockFile 
 * @returns 
 */
exports.getFullUnmockedExceptRds = function (rdsMockFile) {
  const unmocked = require('aws-sdk');
  return new function() {
    this.RDS = exports.getAwsRdsMock(rdsMockFile).RDS;
    this.Route53 = unmocked.Route53;
    this.S3 = unmocked.S3;
    this.CloudFormation = unmocked.CloudFormation;
    this.ResourceGroupsTaggingAPI = unmocked.ResourceGroupsTaggingAPI;
  }
}

/**
 * All CRUD operations are mocked, except for reads. This will get you as close to a real scenario 
 * as can be obtained without actually modifying anything in the cloud account.
 * Requires all resources specified in launch configuration args exist in the cloud account.
 * @returns 
 */
exports.getFullReadOnlyMock = function() {
  const unmocked = require('aws-sdk');
  return new function() {
    this.RDS = unmocked.RDS;
    this.Route53 = exports.getAwsRoute53Mock().Route53;
    this.S3 = exports.getAwsS3Mock().S3;
    this.CloudFormation = exports.getAwsCloudFormationMock().CloudFormation;
    this.ResourceGroupsTaggingAPI = unmocked.ResourceGroupsTaggingAPI;
  }
}

/**
 * RDS & S3: All CRUD operations are mocked.
 * Other: All CRUD operations are mocked, except for reads.
 * Requires all resources specified in launch configuration args exist in the cloud account, except RDS and S3
 * @param {*} rdsMockFile 
 * @returns 
 */
exports.getFullMock = function (rdsMockFile) {
  return new function() {
    this.Route53 = exports.getAwsRoute53Mock().Route53;
    if(rdsMockFile) {
      var DbInstance = new RdsDb();
      var rdsDb = DbInstance.load(require(rdsMockFile));
      this.RDS = exports.getAwsRdsMock(rdsMockFile).RDS;
      this.S3 = exports.getAwsS3Mock(rdsDb).S3;
    }        
    this.CloudFormation = exports.getAwsCloudFormationMock().CloudFormation;
    this.ResourceGroupsTaggingAPI = unmocked.ResourceGroupsTaggingAPI;
  }
}
