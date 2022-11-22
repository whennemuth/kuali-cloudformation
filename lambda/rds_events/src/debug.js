const RdsDb = require('./RdsDatabase.js');
const LifecycleRecord = require('./RdsLifecycleRecord.js');
const HostedZone = require('./HostedZone.js');
const rdsr = require('./RdsLifecycleEvent.js');
const CloudFormationInventoryForKC = require('./CloudFormationInventoryForKC.js');
const CloudFormationInventoryForBatch = require('./CloudFormationInventoryForBatch.js');
const SecurityGroups = require('./SecurityGroup.js');
const MockFactory = require('../mocks/MockFactory.js');

var debugChoice = process.argv[2];

(async () => {
  /* Run a test indentified by the first argument passed in by the launch configuration */
  try {
    switch(debugChoice) {
  
      /**
       * Test the DBInstance class against a mocked rds database.
       */
      case 'database-from-record':
        var DbInstance = new RdsDb();
        var dbMockFile = process.argv[3];
        var rdsDb = await DbInstance.find(MockFactory.getAwsRdsMock(dbMockFile), 'mockArn');
        console.log(JSON.stringify(rdsDb.getData(), null, 2));
        console.log(JSON.stringify(rdsDb.getTags(), null, 2));
        console.log(rdsDb.getEndpointAddress());
        console.log(rdsDb.getLandscape());
        break;
      
      
      /**
       * Test the DBInstance class against an existing rds database.
       */
      case 'database-lookup':
        var dbArn = process.argv[3];
        var AWS = require('aws-sdk');
        var DbInstance = new RdsDb();
        var rdsDb = await DbInstance.find(AWS, dbArn);
        console.log(JSON.stringify(rdsDb.getData(), null, 2));
        console.log(JSON.stringify(rdsDb.getTags(), null, 2));
        console.log(rdsDb.getEndpointAddress());
        console.log(rdsDb.getLandscape());
        break;
  
      /**
       * Test the RdsLifeCycleRecord class load function by mocking the s3 service to return "canned" json details of an rds database 
       */
      case 'record-load-mocked':
        var dbMockFile = process.argv[3];
        var DbInstance = new RdsDb();
        var rdsDb = await DbInstance.find(MockFactory.getAwsRdsMock(dbMockFile), 'mockArn');
        var lcRec = new LifecycleRecord(MockFactory.getAwsS3Mock(rdsDb), rdsDb.getArn());
        var json = await lcRec.load('created');
        console.log(`Retrieval from mocked s3 of rds db creation result ${json}`);
        break;  
  
      /**
       * Test the RdsLifeCycleRecord class load function against the s3 service to return json details of an rds database.
       * NOTE: Depends on an actual file existing in the s3 bucket as indicated by the state and rdsId arguments.
       */
      case 'record-load-s3':
        var state = process.argv[3];
        var rdsId = process.argv[4];
        var AWS = require('aws-sdk');
        var lcRec = new LifecycleRecord(AWS, rdsId);
        var json = await lcRec.load(state);
        console.log(`Retrieval from s3 of rds db creation result ${json}`);
        break;         
  
      /**
       * Upload a sample of rds database details json to the s3 bucket.
       */
      case 'record-persist':
        var dbMockFile = process.argv[3];
        var DbInstance = new RdsDb();
        var rdsDb = await DbInstance.find(MockFactory.getAwsRdsMock(dbMockFile), 'mockArn');
        var AWS = require('aws-sdk');
        var lcRec = new LifecycleRecord(AWS, rdsDb);
        var result = await lcRec.persist();
        console.log(`S3 record creation of rds db creation result ${JSON.stringify(result, null, 2)}`);
        break;  
  
      case 'record-move':
        var dbMockFile = process.argv[3];
        var fromState = process.argv[4];
        var toState = process.argv[5];
        var DbInstance = new RdsDb();
        var rdsDb = await DbInstance.find(MockFactory.getAwsRdsMock(dbMockFile), 'mockArn');
        var AWS = require('aws-sdk');
        var lcRec = new LifecycleRecord(AWS, rdsDb);
        var result = await lcRec.move(fromState, toState);
        console.log(`S3 object move result: ${JSON.stringify(result, null, 2)}`);
        break;  
  
      case 'hostedzone-load':
        var AWS = require('aws-sdk');
        var oldTarget = process.argv[3];
        var hostedzone = await HostedZone.lookup(AWS, process.env.HOSTED_ZONE_NAME);
        var dbRecs = hostedzone.getDbRecordsForTargetEndpoint(oldTarget);
        console.log(JSON.stringify(dbRecs, null, 2));
        break;      
      
      case 'hostedzone-update':
        var AWS = require('aws-sdk');
        // var AWS = MockFactory.getAwsRoute53Mock();
        var oldTarget = process.argv[3];
        var newTarget = process.argv[4];
        var hostedzone = await HostedZone.lookup(AWS, process.env.HOSTED_ZONE_NAME);
        var dbRecs = hostedzone.getDbRecordsForTargetEndpoint(oldTarget);
        if(hostedzone.exists()) {
          var data = await hostedzone.updateDbResourceRecordSetTargets(AWS, dbRecs, oldTarget, newTarget);
          console.log(`Resource record update success\n${JSON.stringify(data, null, 2)}`);
        }
        break;  
  
      case 'create-event-all-mocks':
        var eventMockFile = process.argv[3];
        var mockEvent = require(eventMockFile);
        var dbMockFile = process.argv[4];
        var AWSMock = MockFactory.getFullMock(dbMockFile);
        rdsr.handler(mockEvent, { getMockAWS: () => { return AWSMock; } });
        break;  
  
      /**
       * Simulate an EventBridge rule being triggered that indicates a kuali database has been created.
       * It doesn't matter if the rds database exists in the aws account because it is being mocked.
       * All other api activity (s3, route53, cloudformation) is not mocked and will be executed against the aws account.
       */
      case 'create-event-rds-mocked':
        var eventMockFile = process.argv[3];
        var mockEvent = require(eventMockFile);
        var dbMockFile = process.argv[4];
        var AWSMock = MockFactory.getFullUnmockedExceptRds(dbMockFile);
        rdsr.handler(mockEvent, { getMockAWS: () => { return AWSMock; }});
        break;

      /**
       * Simulate an EventBridge rule being triggered that indicates a kuali database has been created.
       * All api operations that read data are not mocked.
       * All api operations that update, create, or delete data are mocked.
       * This is a safe way to see what a real create event would do against the current resources in the account without anything getting changed.
       */
      case 'create-event-readonly':
        var eventMockFile = process.argv[3];
        var mockEvent = require(eventMockFile);
        var AWSMock = MockFactory.getFullReadOnlyMock();
        rdsr.handler(mockEvent, { getMockAWS: () => { return AWSMock; }});
        break;
  
      case 'delete-event-all-mocks':
        var eventMockFile = process.argv[3];
        var mockEvent = require(eventMockFile);
        var dbMockFile = process.argv[4];
        var AWSMock = MockFactory.getFullMock(dbMockFile); 
        rdsr.handler(mockEvent, { getMockAWS: () => { return AWSMock; }});
        break;  
      
      /**
       * Simulate an EventBridge rule being triggered that indicates a kuali database has been either created or deleted.
       * This is not a unit test - the overall nodejs project is to be run by a lambda function targeted by EventBridge, 
       * so this is a way to see what would happen in that lambda function from end to end.
       * NOTE: The associated rds database must exist in the aws account.
       */
      case 'create-event': case 'delete-event':
        var eventMockFile = process.argv[3];
        var mockEvent = require(eventMockFile);
        rdsr.handler(mockEvent, {});
        break;

      case 'get-stacks-for-kc':
        var baseline = process.argv[3];
        var AWS = require('aws-sdk');
        var inventory = new CloudFormationInventoryForKC(AWS, baseline);
        var stacks = await inventory.getStacks();
        stacks.forEach(stack => {
          console.log(stack.detailsString);
        });
        break;

      case 'update-stacks-for-kc-mocked':
        var baseline = process.argv[3];
        var AWSMock = MockFactory.getFullMock();
        var inventory = new CloudFormationInventoryForKC(AWSMock, baseline);
        var stacks = await inventory.getStacks();
        for (let index = 0; index < stacks.length; index++) {
          const stack = stacks[index];
          const data = await stack.updateRdsVpcSecurityGroupId(AWSMock, 'sg-new-id');
          console.log(JSON.stringify(data, null, 2));
        }
        break;

      case 'update-stacks-for-kc':
        var baseline = process.argv[3];
        var AWS = require('aws-sdk');
        var inventory = new CloudFormationInventoryForKC(AWS, baseline);
        var stacks = await inventory.getStacks();
        for (let index = 0; index < stacks.length; index++) {
          const stack = stacks[index];
          const data = await stack.updateRdsVpcSecurityGroupId(AWS, 'sg-08ab79baa11bad5e0');
          console.log(JSON.stringify(data, null, 2));
        }
        break;
  
      case 'get-stacks-for-batch':
        var AWS = require('aws-sdk');
        var inventory = new CloudFormationInventoryForBatch(AWS);
        var stacks = await inventory.getStacks();
        stacks.forEach(stack => {
          console.log(stack.detailsString);
        });
        break;

      case 'update-stacks-for-batch-mocked':
        var AWSMock = MockFactory.getFullMock();
        var inventory = new CloudFormationInventoryForBatch(AWSMock);
        var stacks = await inventory.getStacks();
        for (let index = 0; index < stacks.length; index++) {
          const stack = stacks[index];
          const data = await stack.updateRdsVpcSecurityGroupId(AWSMock, 'sg-new-id');
          console.log(JSON.stringify(data, null, 2));
        }
        break;

      case 'get-stale-security-groups':
        var AWS = require('aws-sdk');
        var vpcId = process.argv[3];
        // var filter = process.argv[4];
        var sgs = await new SecurityGroups(
          AWS, 
          vpcId, 
          { qualifies: sg => { return true; }}
        );
        sgs.each(sg => {
          console.log(`GroupId: ${sg.GroupId}, GroupName: ${sg.GroupName}`);
          console.log(`FromGroupId: ${sg.StaleIpPermissions[0].UserIdGroupPairs[0].GroupId}`);
        })
        break;
            
      case 'zip':
        const zip = require('../../zip/zip.js');
        console.log('zip done.');
        break;
        
      case 'test':
        // const date = require('date-and-time');
        // console.log(date.format(new Date(),'YYYY-MM-DD-HH.mm.ss'));
        // break;
        var test = require('./test.js');
        test.handler({
          ResourceProperties: {
            RdsVpcSecurityGroupId: 'sg-0bdd9cbe0117aa755',
            DBIdentifier: 'kuali-oracle-warren',
            SecurityGroupGroupIds: [
              'kuali-oracle-stg',
              // 'sg-000537769a1c2d858',
              'sg-0e4d6b8a99395a608'
            ],
            // EC2SecurityGroupGroupId: 'sg-000537769a1c2d858',
            // ALBSecurityGroupGroupId: 'sg-0e4d6b8a99395a608',
            BucketName: 'kuali-conf',
            BucketPath: 'rds-lifecycle-events/created'
          },
          RequestType: 'Create'
        },{});
        break;
    }
  }
  catch (err) {
    console.log(err, err.stack);
  }
})();
