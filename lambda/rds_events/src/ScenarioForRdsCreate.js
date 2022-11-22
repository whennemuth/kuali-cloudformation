


async function handleRdsSecurityGroupReferences(parms) {
  // var oldSecGrp = parms.OldRdsDb.
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
      NewRdsDb: newRdsDb
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

        await handleRoute53(AWS, records.OldRdsDb, records.NewRdsDb);

        await handleRdsSecurityGroupReferencesForKC(AWS, records.OldRdsDb, records.NewRdsDb);

        await handleRdsSecurityGroupReferencesForBatch(AWS, records.OldRdsDb, records.NewRdsDb);

        await archivePendingDatabaseRecord(AWS, records.OldRdsDb);
      }
  
    })();
  }
}