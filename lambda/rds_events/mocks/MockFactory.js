const RdsDb = require('../src/RdsDatabase.js');

/**
 * The response to an AWS request is not itself a promise, but it has a promise method that does return one.
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

exports.getAwsS3Mock = function(rdsDb) {
  return {      
    S3: function() {
      this.headObject = (params) => {
        // As long as there is no error, pass anything that is truthy, which causes true as the return value.
        return getAwsResponse({});
      };
      this.getObject = (params) => {
        return getAwsResponse({ Body: JSON.stringify(rdsDb.getData(), null, 2) });
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
 * This mock mocks only the changeResourceRecordSets.
 * All other route53 functions are real and require the corresponding resources to exist in the cloud account.
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

exports.getFullMock = function (rdsMockFile) {
  return new function() {
    var DbInstance = new RdsDb();
    var rdsDb = DbInstance.load(require(rdsMockFile));
    this.Route53 = exports.getAwsRoute53Mock().Route53;    
    this.RDS = exports.getAwsRdsMock(rdsMockFile).RDS;
    this.S3 = exports.getAwsS3Mock(rdsDb).S3;
  }
}
