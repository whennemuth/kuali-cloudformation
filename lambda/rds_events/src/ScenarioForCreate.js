/**
 * This module performs all actions necessary when a new rds database for kuali has been created.
 */

const RdsDb = require('./RdsDatabase.js');
const LifecycleRecord = require('./RdsLifecycleRecord.js');
const header="\n*****************************************************************************";

async function getRdsDatabase (AWS, dbArn) {
  var dbInstance = new RdsDb();
  var newRdsDb = await dbInstance.find(AWS, dbArn);
  if(newRdsDb.isKualiDatabase()) {
    console.log(`${header}\n    Event for creation of the following rds database detected:${header}\n${newRdsDb.getJSON()}`);
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
    console.log(`${header}\n    Found old rds database record in s3:${header}\n${json}`);
  }
  else {
    var msg = "RDS database created, but there is no record in s3 of a prior database it replaces.";
    console.log(`${header}\n    Bad state:${header}\n${msg}`);
  }
  return json;
}

function rdsLandscapeMismatch(rds1, rds2) {
  if(rds1.hasSameLandscapeAs(rds2)) {
    return false;
  }
  var msg = "Bad state: An old rds database record was found in pending state.\nIt matches in name to the newly created database, but not by landscape - how did this happen?";
  console.log(`${header}\n    Bad state:${header}\n${msg}`);
  return true;
}

async function getHostedZoneWithDbRecord(AWS, hostedZoneName, landscape) {
  var HostedZone = require('./HostedZone');
  var hostedzone = await new HostedZone.lookup(AWS, hostedZoneName);    
  var dbRec = hostedzone.getDbRecordForLandscape(landscape);
  return {
    hostedZone: hostedzone,
    databaseRecord: dbRec,
    missingDbRecord: () => {
      if(dbRec) {
        console.log(`${header}\n    Found ${hostedZoneName} rds CNAME record for the ${landscape} landscape:${header}\n${JSON.stringify(dbRec, null, 2)}`);
        return false;
      }
      else {
        var msg = `Rds database lifecycle records indicate a hostedzone resource record should be locatable for update by a ${landscape} landscape, but none can be found - how did this happen?`;
        console.log(`${header}\n    Bad state:${header}\n${msg}`);
        return true
      }
    }
  }
}

async function updateHostedZoneDbRecord(parms) {
  var oldEP = parms.databaseRecord.ResourceRecords[0].Value;
  var oldName = parms.databaseRecord.Name;
  var newEP = parms.newRdsDatabase.getEndpointAddress();
  console.log(`Resource record ${oldName} maps to defunct database:\n  ${oldEP} \nand needs to be updated to:\n  ${newEP}`);
  var data = await parms.hostedZone.updateDbResourceRecordSetTarget(parms.AWS, parms.databaseRecord, newEP);
  console.log(`${header}\n    Resource record update success${header}\n${JSON.stringify(data, null, 2)}`);
}

async function archivePendingDatabaseRecord(AWS, oldRdsDb) {
  var result = await new LifecycleRecord(AWS, oldRdsDb).move('pending', 'final');
  console.log(`Archive result: ${JSON.stringify(result, null, 2)}`);
}


module.exports = function(AWS) {
  this.execute = (dbArn) => {
    (async () => {
      try {
        // 1) Lookup the details of the newly created database.
        var newRdsDb = await getRdsDatabase(AWS, dbArn);
        if( ! newRdsDb) return;

        // 2) Create new lifecycle record in s3 for the new RDS instance
        await persistNewLifecycleRecord(AWS, newRdsDb);

        // 3) Search for a prior lifecycle record for a deleted RDS database that the new one replaces (same landscape).
        var databaseJson = await loadLifecycleRecord(AWS, newRdsDb, 'pending');
        if( ! databaseJson) return;

        // 4) Quit if the old database record is of a different landscape (for some weird reason).
        var oldRdsDb = new RdsDb().load(JSON.parse(databaseJson));
        if(rdsLandscapeMismatch(newRdsDb, oldRdsDb)) return;

        // 5) Get the hosted zone along with the database CNAME record.
        var hsdata = await getHostedZoneWithDbRecord(AWS, process.env.HOSTED_ZONE_NAME, newRdsDb.getLandscape());
        if(hsdata.missingDbRecord()) return;

        // 6) A hosted zone resource record was found that maps database requests to the defunct rds endpoint. Update it to the new rds endpoint.
        await updateHostedZoneDbRecord({
          AWS: AWS,
          hostedZone: hsdata.hostedZone,
          databaseRecord: hsdata.databaseRecord,
          newRdsDatabase: newRdsDb
        })

        // 7) Now that the hosted zone resource record is updated, move the corresponding lifecyle record into "final" state.
        await archivePendingDatabaseRecord(AWS, oldRdsDb);
      }
      catch(err) {
        console.log(err, err.stack);
      }
    })();
  }
}