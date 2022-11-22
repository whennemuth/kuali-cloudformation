/**
 * This module performs all actions necessary when a new rds database for kuali has been created.
 * The actions performed restore routing and security relationships that existed with the predecessor
 * rds database before it was deleted.
 * -----------------------
 * PREDECESSOR DEFINITION: 
 * -----------------------
 *   A predecessor database would be one that was based on the same landscape as the new one.
 *   The convention being observed here is that no kuali rds database will be running that has more
 *   than one client application stack (uniquely identified by landscape) configured with a database
 *   connection hostname that routes through dns associated with it at the same time. In other words,
 *   the landscape tag on an rds database indicates the one application stack it services via route53.
 *   While it is possible to "point" mulitple application stacks, each with this database dns routing, 
 *   each at the same rds database, the landscape value attached to the rds database would become 
 *   semi-meaningless as it would only indicate one of the now multiple route53 records that apply. 
 */

const RdsDb = require('./RdsDatabase.js');
const LifecycleRecord = require('./RdsLifecycleRecord.js');
const HostedZone = require('./HostedZone');
const CloudFormationInventoryForKC = require('./CloudFormationInventoryForKC.js');
const CloudFormationInventoryForBatch = require('./CloudFormationInventoryForBatch.js');

const header="\n*****************************************************************************";

async function getRdsDatabase (AWS, dbArn) {
  var dbInstance = new RdsDb();
  var newRdsDb = await dbInstance.find(AWS, dbArn);
  if(newRdsDb.isKualiDatabase()) {
    console.log(`\nNew rds database:\n${newRdsDb.getShortJSON()}`);
    return newRdsDb;
  }
  else {
    console.log(`New rds database creation detected: ${dbArn}\nBut is not a kuali database, cancelling...`);
    return null;
  }
};

async function persistNewLifecycleRecord(AWS, newRdsDb) {
  var result = await new LifecycleRecord(AWS, newRdsDb).persist();
  console.log(`${header}\n    S3 record creation of rds db creation result:${header}\n${JSON.stringify(result, null, 2)}`);
}

async function loadLifecycleRecord(AWS, newRdsDb, state) {
  var json = await new LifecycleRecord(AWS, newRdsDb).load(state);
  if(json) {
    var shortJson = new RdsDb().load(JSON.parse(json)).getShortJSON();
    console.log(`${header}\n    Found old rds database record in s3:${header}\n${shortJson}`);
  }
  else {
    var msg = "RDS database created, but there is no record in s3 of a prior database it replaces.";
    console.log(`${header}\n    Bad state:${header}\n${msg}`);
  }
  return json;
}

function checkRdsLandscapeMismatch(rds1, rds2) {
  if(rds1.hasSameLandscapeAs(rds2)) {
    return false;
  }
  var msg = "Warning, suspicious state: An old rds database record was found in pending state.\nDespite matching the newly created database, it has a different landscape - how did this happen?";
  console.log(`${header}\n    Bad state:${header}\n${msg}`);
}

async function getHostedZoneAndDbRecords(AWS, hostedZoneName, oldEndpoint) {
  var hostedzone = await new HostedZone.lookup(AWS, hostedZoneName);
  var dbRecs = hostedzone.getDbRecordsForTargetEndpoint(oldEndpoint);
  return {
    hostedZone: hostedzone,
    databaseRecords: dbRecs,
    missingDbRecord: () => {
      if(dbRecs.length > 0) {
        console.log(`${header}\n    Found ${hostedZoneName} rds CNAME record(s) for the ${oldEndpoint} endpoint:${header}\n${JSON.stringify(dbRecs, null, 2)}`);
        return false;
      }
      else {
        var msg = `Rds database lifecycle records indicate a hostedzone resource record should be locatable for update by a ${endpoint} target endpoint, but none can be found - how did this happen?`;
        console.log(`${header}\n    Bad state:${header}\n${msg}`);
        return true;
      }
    }
  }
}

async function updateHostedZoneDbRecords(parms) {
  var oldEP = parms.oldTargetEndpoint
  var newEP = parms.newTargetEndpoint
  console.log(`${header}\n    Updating rds CNAME record(s) for ${parms.hostedZone.getName()} ${header}`);
  if(oldEP == newEP) {
    console.log(`S3 based lifecycle records show that the new rds db ( ${newEP} ) retains the same target endpoint as the db it replaces. No route53 update necessary.`);
    return;
  }

  // Get a "reduced" array of just the db names.
  var oldRecNames = [];
  oldRecNames = parms.databaseRecords.reduce((prev, curr) => {
    prev.push(curr.Name);
    return prev;
  }, oldRecNames);
  
  // Update the target endpoint values for each applicable resource recordset.
  console.log(`Resource record(s) ${JSON.stringify(oldRecNames)} map to defunct database:\n  ${oldEP} \nand need to be updated to:\n  ${newEP}`);
  var data = await parms.hostedZone.updateDbResourceRecordSetTargets(parms.AWS, parms.databaseRecords, oldEP, newEP);
  console.log(`${header}\n    Resource record update success${header}\n${JSON.stringify(data, null, 2)}`);
}

/**
 * When the hosted zone resource record and rds vpc security group ingress rules are updated, move the corresponding pending lifecycle record into "final" state.
 * @param {*} AWS 
 * @param {*} oldRdsDb 
 */
async function archivePendingDatabaseRecord(AWS, oldRdsDb) {
  console.log(`${header}\n    Archiving pending rds db lifecycle record ${header}`);
  var result = await new LifecycleRecord(AWS, oldRdsDb).move('pending', 'final');
  console.log(`Archive result: ${JSON.stringify(result, null, 2)}`);
}

/**
 * A new kuali rds database has been created. Search for any cloudformation stacks that were created to use 
 * the new databases prececessor and run a stack update for each, passing in the vpc security group id for the new rds database.
 * The stack update will attach a SecurityGroupIngress rule to the new rds vpc security group so that ingress is restored from
 * the associated ec2 security group of the application.
 * @param {*} parms 
 */
async function handleRdsSecurityGroupReferences(parms) {
  console.log(`${header}\n    Updating rds vpc security group ingress rules for ${parms.StackType} ${header}`);
  var stacks = await parms.Inventory.getStacks();
  for(const stackItem in stacks) {
    var stack = stacks[stackItem];
    if(stack.securityGroupMatch(parms.OldRdsDb)) {
      if(stack.securityGroupMismatch(parms.NewRdsDb)) {
        console.log(`${stack.getName()} used a rds vpc security group id: ${stack.getRdsSecurityGroupId()}, that needs to be updated to the one from the new rds db: ${parms.NewRdsDb.getFirstSecurityGroupId()}`);
        var data = await stack.updateRdsVpcSecurityGroupId(parms.AWS, parms.NewRdsDb.getFirstSecurityGroupId());
        console.log(`Stack update in progress: ${JSON.stringify(data, null, 2)}`);
      }
      else {
        console.log(`
A new rds database was created, but seems to have the same vpc security group id 
as a prior rds database to which the ${stack.getName()} stack attached ingress rules for. 
This could only happen if:
  1) The rds db was created in a stack that is nested in the application stack.
  2) The parent application stack finished before the db creation event was picked up by the lambda function.
Result is no action.
  `);
      }
    }
    else {
      console.log(`
Stack "${stack.getName()}" does not exhibit a "${stack.getRdsVpcSecGrpParmName()}" matching that of the replaced rds database.
   ${stack.getName()}: ${stack.getRdsSecurityGroupId()}
   Defunct database: ${JSON.stringify(parms.OldRdsDb.getVpcSecurityGroups())}
Probably means that ${stack.getName()} was never associated with ${parms.NewRdsDb.getID()} or any of its predecessors.
      `);
    }
  }
}

async function handleRdsLifecycleRecordKeeping(AWS, dbArn) {
  return new Promise(
    (resolve) => {
      try {
        resolve((async () => {
          var newRdsDb = await getRdsDatabase(AWS, dbArn);

          await persistNewLifecycleRecord(AWS, newRdsDb);

          var databaseJson = await loadLifecycleRecord(AWS, newRdsDb, 'pending');

          var oldRdsDb = null;
          if(databaseJson) {
            oldRdsDb = new RdsDb().load(JSON.parse(databaseJson));
          }

          return {
            OldRdsDb: oldRdsDb,
            NewRdsDb: newRdsDb,
            areComplete: () => {
              if( ! oldRdsDb) return false;
              if( ! newRdsDb) return false;
              return true;
            }
          }
        })());
      }
      catch(err) {
        console.log(err, err.stack);
        return { areComplete: () => { return false; }};
      }
    }
  );
}

/**
 * A new kuali rds database has been created. Search for and update any route 53 resource recordsets that route traffic
 * to its predecessors private endpoint url so routing goes to the new database endpoint. A predecessor database would be
 * one that has been deleted, but s3-based recordkeeping shows that it was for the same landscape.
 * @param {*} AWS 
 * @param {*} newRdsDb 
 * @returns 
 */
async function handleRoute53(AWS, oldRdsDb, newRdsDb) {
  try {
    // 1) Despite finding a match, warn if the old database record content indicates a different landscape as that of the new rds database.
    checkRdsLandscapeMismatch(newRdsDb, oldRdsDb);

    // 2) Get the hosted zone along with the database CNAME record.
    var hsdata = await getHostedZoneAndDbRecords(AWS, process.env.HOSTED_ZONE_NAME, oldRdsDb.getEndpointAddress());
    if(hsdata.missingDbRecord()) return;

    // 3) A hosted zone resource record was found that maps database requests to the defunct rds endpoint. Update it to the new rds endpoint.
    await updateHostedZoneDbRecords({
      AWS: AWS,
      hostedZone: hsdata.hostedZone,
      databaseRecords: hsdata.databaseRecords,
      oldTargetEndpoint: oldRdsDb.getEndpointAddress(),
      newTargetEndpoint: newRdsDb.getEndpointAddress()
    })
  }
  catch(err) {
    console.log(err, err.stack);
  }
}

/**
 * Run a update against any kuali application stacks to add the appropriate ingress rules on to the rds vpc security group.
 * @param {*} AWS An aws sdk object.
 * @param {*} newRdsDb Decorated details for the newly created kuali rds database.
 */
async function handleRdsSecurityGroupReferencesForKC(AWS, oldRdsDb, newRdsDb) {
  try {
    await handleRdsSecurityGroupReferences({
      StackType: 'kuali application',
      AWS: AWS,
      OldRdsDb: oldRdsDb,
      NewRdsDb: newRdsDb,
      Inventory:  new CloudFormationInventoryForKC(AWS, newRdsDb.getBaseline())
    });
  } 
  catch (err) {
    console.log(err, err.stack);
  }
}

async function handleRdsSecurityGroupReferencesForBatch(AWS, oldRdsDb, newRdsDb) {
  try {
    await handleRdsSecurityGroupReferences({
      StackType: 'research admin reports',
      AWS: AWS,
      OldRdsDb: oldRdsDb,
      NewRdsDb: newRdsDb,
      Inventory:  new CloudFormationInventoryForBatch(AWS)    
    });
  } 
  catch (err) {
    console.log(err, err.stack);
  }
}

module.exports = function(AWS) {
  this.execute = (dbArn) => {
    (async () => {

      var records = await handleRdsLifecycleRecordKeeping(AWS, dbArn);

      if(records.areComplete()) {
console.log("------------- TEMPORARILY DISABLED ------------- ");
return;

        await handleRoute53(AWS, records.OldRdsDb, records.NewRdsDb);

        await handleRdsSecurityGroupReferencesForKC(AWS, records.OldRdsDb, records.NewRdsDb);

        await handleRdsSecurityGroupReferencesForBatch(AWS, records.OldRdsDb, records.NewRdsDb);

        await archivePendingDatabaseRecord(AWS, records.OldRdsDb);
      }
  
    })();
  }
}