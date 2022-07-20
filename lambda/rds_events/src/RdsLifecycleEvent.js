const DBCreateScenario = require('./ScenarioForCreate.js');
const DBDeleteScenario = require('./ScenarioForDelete.js');

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
      this.isTest = () => {
        return detail.EventID == 'RDS-EVENT-TEST';
      }
      this.getArn = () => { return detail.SourceArn; }
    }
  }
};


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
    else if(dbEvent.isTest()) {
      console.log('THIS IS A TEST!');
    }
    else if(dbEvent.isRdsInstanceEvent()) {
      console.log(`Rds instance event noticed: ${dbEvent.detail.EventID}: ${dbEvent.detail.SourceIdentifier}`);
    }
  }
  catch(e) {
    console.debug(e);
  }
}
