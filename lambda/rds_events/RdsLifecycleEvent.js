const RdsDb = require('./RdsDatabase.js');
const LifecycleRecord = require('./RdsLifecycleRecord.js');

const header="\n*****************************************************************************";

/**
 * 
 * @param {*} event 
 */
var DBEvent = function(event) {
  this.isRdsInstanceEvent = () => { return false; }
  this.isDelete = () => { return false; }
  this.isCreate = () => { return false; }
  this.getArn = () => { return null; }
  this.getJson = () => { return JSON.stringify(event, null, 2); }
  this.logEvent = eventType => {
    console.log(`${header}\n    Detected the following rds database ${eventType} event:${header}\n${this.getJson()}`);
  }
  with(event) {
    if(source == 'aws.rds' && detail.SourceType == 'DB_INSTANCE') {
      this.isRdsInstanceEvent = () => { return true; }
      this.isDelete = () => { 
        return detail.EventCategories[0] == 'deletion' || detail.EventID == 'RDS-EVENT-0003';
      };
      this.isCreate = () => {
        switch(detail.EventID) {
          case 'RDS-EVENT-0005': return true; // created
          case 'RDS-EVENT-0043': return true; // restored from a DB snapshot
          case 'RDS-EVENT-0019': return true; // restored from a point-in-time backup
          default: return false;
        }
      };
      this.getArn = () => { return detail.SourceArn; }
    }
  }
};

const DBCreateScenario = function(AWS) {
  var dbInstance = new RdsDb();
  this.execute = (dbArn) => {
    dbInstance.find(AWS, dbArn, (err, newRdsDb) => {
      if(err) {
        console.log(err, err.stack);
      }
      else if(newRdsDb.isKualiDatabase()) {
        console.log(`${header}\n    Event was for creation of the following rds database:${header}\n${newRdsDb.getJSON()}`);
        // 1) Create new lifecycle record in s3 for the new RDS instance
        new LifecycleRecord(AWS, newRdsDb).persist((err, result) => {
          if(err) {
            console.log(err, err.stack);
          }
          else {
            console.log(`${header}\n    S3 record creation of rds db creation result:${header}\n${JSON.stringify(result, null, 2)}`);
            // 2) Search for a prior lifecycle record for a deleted RDS database that the new one replaces (same landscape).
            new LifecycleRecord(AWS, newRdsDb).load('pending', (err, json) => {
              if(err) {
                console.log(err, err.stack);
              }
              else {
                if(json) {
                  console.log(`${header}\n    Found old rds database record in s3:${header}\n${json}`);
                  var oldRdsDb = dbInstance.load(JSON.parse(json));
                  if(newRdsDb.getLandscape() == oldRdsDb.getLandscape()) {
                    var HostedZone = require('./HostedZone');
                    // 3) A matching prior lifecycle record is found, so search for a route53 record containing the defunct rds endpoint target info. 
                    new HostedZone.lookup(AWS, process.env.HOSTED_ZONE_NAME, (err, hostedzone) => {
                      if(err) {
                        console.log(err, err.stack);
                      }
                      else {
                        var dbRec = hostedzone.getDbRecordForLandscape(newRdsDb.getLandscape());
                        if(dbRec) {
                          console.log(`${header}\n    Found ${process.env.HOSTED_ZONE_NAME} rds CNAME record for the ${oldRdsDb.getLandscape()} landscape:${header}\n${JSON.stringify(dbRec, null, 2)}`);
                          var oldEP = dbRec.ResourceRecords[0].Value;
                          var newEP = newRdsDb.getEndpointAddress();
                          console.log(`Resource record ${dbRec.Name} maps to defunct database:\n  ${oldEP} \nand needs to be updated to:\n  ${newEP}`);
                          // 4) A hosted zone resource record was found that maps database requests to the defunct rds endpoint. Update it to the new rds endpoint.
                          hostedzone.updateDbResourceRecordSetTarget(AWS, dbRec, newEP, (err, data) => {
                            if(err) {
                              console.log(err, err.stack);
                            }
                            else {
                              console.log(`${header}\n    Resource record update success${header}\n${JSON.stringify(data, null, 2)}`);
                              // 5) Now that the hosted zone resource record is updated, move the corresponding lifecyle record into "final" state.
                              new LifecycleRecord(AWS, oldRdsDb).find('pending', (err, result) => {
                                if(err) {
                                  console.log(err, err.stack);
                                }
                                else if(result == 'found') {
                                  console.log(`${header}\n    Found pending lifecycle record. Moving to final state...${header}`);
                                  new LifecycleRecord(AWS, oldRdsDb).move('pending', 'final', (err, result) => {
                                    if(err) {
                                      console.log(err, err.stack);
                                    }
                                    else {
                                      console.log(`S3 record creation of rds db creation result ${result}`);
                                    }
                                  });             
                                }
                              });
                            }
                          });
                        }
                        else {
                          var msg = 'Rds database lifecycle records indicate a hostedzone resource record should be locatable for update by a ${newRdsDb.getLandscape()} landscape, but none can be found - how did this happen?';
                          console.log(`${header}\n    Bad state:${header}\n${msg}`);
                        }
                      }
                    });                
                  }
                  else {
                    var msg = "Bad state: An old rds database record was found in pending state.\nIt matches in name to the newly created database, but not by landscape - how did this happen?";
                    console.log(`${header}\n    Bad state:${header}\n${msg}`);
                  }
                }
                else {
                  var msg = "RDS database created, but there is no record in s3 of a prior database it replaces.";
                  console.log(`${header}\n    Bad state:${header}\n${msg}`);
                }
              }
            })
          }            
        });
      }
      else {
        true;
        // var msg = 'RDS database creation detected, but does not appear to be a kuali db: ' + rdsDb.getID();
        // console.log(`${header}\n    Bad state:${header}\n${msg}`);
      }    
    });
  };
};

const DBDeleteScenario = function(AWS) {
  this.execute = (dbArn) => {
    new LifecycleRecord(AWS, dbArn).find('created', (err, result) => {
      if(err) {
        console.log(err, err.stack);
      }
      else if(result == 'found') {
        console.log(`${header}\n    Found database creation lifecycle record. Moving to pending state...${header}`);
        new LifecycleRecord(AWS, dbArn).move('created', 'pending', (err, result) => {
          if(err) {
            console.log(err, err.stack);
          }
          else {
            console.log(`S3 record creation of rds db creation result ${result}`);
          }
        });             
      }
    });
  };
}

exports.handler = function(event, context) {
  try {    
    if(context && context.getMockAWS) {
      var AWS = context.getMockAWS();
    }
    else {
      var AWS = require('aws-sdk');
    }
    var dbEvent = new DBEvent(event);
    if(dbEvent.isCreate()) {
      dbEvent.logEvent('creation');
      new DBCreateScenario(AWS).execute(dbEvent.getArn());
    }
    else if(dbEvent.isDelete()) {
      dbEvent.logEvent('deletion');
      new DBDeleteScenario(AWS).execute(dbEvent.getArn());
    }
    else if(dbEvent.isRdsInstanceEvent()) {
      console.log(`Rds instance event noticed: ${dbEvent.detail.EventID}: ${dbEvent.detail.SourceIdentifier}`);
    }
  }
  catch(e) {
    console.debug(e);
  }
}
