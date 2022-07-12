const RdsDb = require('./RdsDatabase.js');
const LifecycleRecord = require('./RdsLifecycleRecord.js');
const HostedZone = require('./HostedZone');

var debugChoice = process.argv[2];

function getAwsRdsMock(mockfile) {
  return {
    RDS: function() {
      this.describeDBInstances = (params, callback) => {
        var record = require(mockfile);
        callback(null, { DBInstances: [ record ] });
      }
    }
  };
}

function getAwsS3Mock(rdsDb) {
  return {      
    S3: function() {
      this.headObject = (params, callback) => {
        callback(null, {}); // A null err object means "true"
      };
      this.getObject = (params, callback) => {
        callback(null, { Body: JSON.stringify(rdsDb.getData(), null, 2) });
      };
      this.putObject = (params, callback) => {
        callback(null, { data: "Mock s3 putObject callback" })
      };
    }
  };
}

function FullMock(rdsMockFile, callback) {
  var DbInstance = new RdsDb();
  DbInstance.find(getAwsRdsMock(rdsMockFile), 'mockArn', (err, rdsDb) => {
    if(err) {
      console.log(err, err.stack);
      callback(err, null);
    }
    else {
      callback(null, {
        RDS: getAwsRdsMock(rdsMockFile).RDS,
        S3: getAwsS3Mock(rdsDb).S3,
        Route53: new require('aws-sdk').Route53
      })
    }      
  });
}

/* Run a test indentified by the first argument passed in by the launch configuration */
switch(debugChoice) {

  /**
   * Test the DBInstance class against a mocked rds database.
   */
  case 'database-from-record':
    var DbInstance = new RdsDb();
    var dbMockFile = process.argv[3];
    DbInstance.find(getAwsRdsMock(dbMockFile), 'mockArn', (err, rdsDb) => {
      if(err) {
        console.log(err, err.stack);
      }
      else {
        console.log(JSON.stringify(rdsDb.getData(), null, 2));
        console.log(JSON.stringify(rdsDb.getTags(), null, 2));
        console.log(rdsDb.getEndpointAddress());
        console.log(rdsDb.getLandscape());
      }      
    });
    break;
  
  
  /**
   * Test the DBInstance class against an existing rds database.
   */
  case 'database-lookup':
    var dbArn = process.argv[3];
    var AWS = require('aws-sdk');
    var DbInstance = new RdsDb();
    DbInstance.find(AWS, dbArn, (err, rdsDb) => {
      if(err) {
        console.log(err, err.stack);
      }
      else {
        console.log(JSON.stringify(rdsDb.getData(), null, 2));
        console.log(JSON.stringify(rdsDb.getTags(), null, 2));
        console.log(rdsDb.getEndpointAddress());
        console.log(rdsDb.getLandscape());
      }      
    });
    break;

  /**
   * Test the RdsLifeCycleRecord class load function by mocking the s3 service to return "canned" json details of an rds database 
   */
  case 'record-load-mocked':
    var dbMockFile = process.argv[3];
    var DbInstance = new RdsDb();
    DbInstance.find(getAwsRdsMock(dbMockFile), 'mockArn', (err, rdsDb) => {
      new LifecycleRecord(getAwsS3Mock(rdsDb), rdsDb.getArn()).load('created', (err, json) => {
        if(err) {
          console.log(err, err.stack);
        }
        else {
          console.log(`Retrieval from mocked s3 of rds db creation result ${json}`);
        }
      });           
    });
    break;


  /**
   * Test the RdsLifeCycleRecord class load function against the s3 service to return json details of an rds database.
   * NOTE: Depends on an actual file existing in the s3 bucket as indicated by the state and rdsId arguments.
   */
  case 'record-load-s3':
    var state = process.argv[3];
    var rdsId = process.argv[4];
    var AWS = require('aws-sdk');
    new LifecycleRecord(AWS, rdsId).load(state, (err, json) => {
      if(err) {
        console.log(err, err.stack);
      }
      else {
        console.log(`Retrieval from s3 of rds db creation result ${json}`);
      }
    });           
    break;
      

  /**
   * Upload a sample of rds database details json to the s3 bucket.
   */
  case 'record-persist':
    var dbMockFile = process.argv[3];
    var DbInstance = new RdsDb();
    DbInstance.find(getAwsRdsMock(dbMockFile), 'mockArn', (err, rdsDb) => {
      var AWS = require('aws-sdk');
      new LifecycleRecord(AWS, rdsDb).persist((err, result) => {
        if(err) {
          console.log(err, err.stack);
        }
        else {
          console.log(`S3 record creation of rds db creation result ${result}`);
        }
      });           
    });
    break;


  case 'record-move':
    var dbMockFile = process.argv[3];
    var fromState = process.argv[4];
    var toState = process.argv[5];
    var DbInstance = new RdsDb();
    DbInstance.find(getAwsRdsMock(dbMockFile), 'mockArn', (err, rdsDb) => {
      var AWS = require('aws-sdk');
      new LifecycleRecord(AWS, rdsDb).move(fromState, toState, (err, result) => {
        if(err) {
          console.log(err, err.stack);
        }
        else {
          console.log(`S3 object move result: ${result}`);
        }
      });           
    });
    break;


  case 'hostedzone-load':
    var AWS = require('aws-sdk');
    var landscape = process.argv[3];
    new HostedZone.lookup(AWS, process.env.HOSTED_ZONE_NAME, (err, hostedzone) => {
      if(err) {
        console.log(err, err.stack);
      }
      else {
        var dbRec = hostedzone.getDbRecordForLandscape(landscape);
        var dbRecJson = JSON.stringify(dbRec, null, 2);
        console.log(dbRecJson);
      }
    });
    break;
  
  
  case 'hostedzone-update':
    var AWS = require('aws-sdk');
    var landscape = process.argv[3];
    var newTarget = process.argv[4];
    new HostedZone.lookup(AWS, process.env.HOSTED_ZONE_NAME, (err, hostedzone) => {
      if(err) {
        console.log(err, err.stack);
      }
      else {
        var dbRec = hostedzone.getDbRecordForLandscape(landscape);
        hostedzone.updateDbResourceRecordSetTarget(AWS, dbRec, newTarget, (err, data) => {
          if(err) {
            console.log(err, err.stack);
          }
          else {
            console.log(`Resource record update success\n${JSON.stringify(data, null, 2)}`);
          }
        });
      }
    });
    break;


  case 'create-event-all-mocks':
    var eventMockFile = process.argv[3];
    var mockEvent = require(eventMockFile);
    var dbMockFile = process.argv[4];
    new FullMock(dbMockFile, (err, mock) => {
      var rdsr = require('./RdsLifecycleEvent.js');
      rdsr.handler(mockEvent, { getMockAWS: () => { return mock; }});
    })    
    break;


  /**
   * Simulate an EventBridge rule being triggered that indicates a kuali database has been either created or deleted.
   * It doesn't matter if the rds database exists in the aws account because it is being mocked.
   * All other api activity (s3, route53) is not mocked and will be executed against the aws account.
   */
  case 'create-event-rds-mocked':
    var rdsr = require('./RdsLifecycleEvent.js');
    var eventMockFile = process.argv[3];
    var mockEvent = require(eventMockFile);
    var dbMockFile = process.argv[4];
    var AWSMock = getAwsRdsMock(dbMockFile);
    rdsr.handler(mockEvent, { getMockAWS: () => { return AWSMock; }});
    break;

  
  /**
   * Simulate an EventBridge rule being triggered that indicates a kuali database has been either created or deleted.
   * This is not a unit test - the overall nodejs project is to be run by a lambda function targeted by EventBridge, 
   * so this is a way to see what would happen in that lambda function from end to end.
   * NOTE: The associated rds database must exist in the aws account.
   */
  case 'create-event': case 'delete-event':
    var rdsr = require('./RdsLifecycleEvent.js');
    var eventMockFile = process.argv[3];
    var mockEvent = require(eventMockFile);
    rdsr.handler(mockEvent, {});
    break;


  case 'delete-event-all-mocks':
    var eventMockFile = process.argv[3];
    var mockEvent = require(eventMockFile);
    var dbMockFile = process.argv[4];
    new FullMock(dbMockFile, (err, mock) => {
      var rdsr = require('./RdsLifecycleEvent.js');
      rdsr.handler(mockEvent, { getMockAWS: () => { return mock; }});
    })    
    break;
  
  
  case 'test':
    const date = require('date-and-time');
    console.log(date.format(new Date(),'YYYY-MM-DD-HH.mm.ss'));
    break;
}
