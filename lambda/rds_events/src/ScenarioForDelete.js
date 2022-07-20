/**
 * This module performs all actions necessary when a rds database for kuali has been deleted.
 */

const LifecycleRecord = require('./RdsLifecycleRecord.js');
const header="\n*****************************************************************************";

async function lifeCycleRecordExists(AWS, dbArn, state) {
  var result = await new LifecycleRecord(AWS, dbArn).find(state);
  if(result == 'found') {
    console.log(`${header}\n    Found database creation lifecycle record. Moving to pending state...${header}`);
    return true;
  }
  return false;
}

async function putDatabaseRecordInPendingState(AWS, dbArn) {
  var result = await new LifecycleRecord(AWS, dbArn).move('created', 'pending');
  console.log(`New pending state result: ${JSON.stringify(result, null, 2)}`);
}

module.exports = function(AWS) {
  this.execute = (dbArn) => {
    (async () => {
      try {
        // 1) Exit if no 'created' lifecycle record exists in s3 to move to pending.
        if(await lifeCycleRecordExists(AWS, dbArn, 'created')) {
          await putDatabaseRecordInPendingState(AWS, dbArn);
        }
      }
      catch(err) {
        console.log(err, err.stack);
      }
    })();
  }
}