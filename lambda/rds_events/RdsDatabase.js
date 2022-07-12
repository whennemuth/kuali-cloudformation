const { load } = require("./HostedZone");

const Database = function(data) {
  this.getData = () => {
    return data;
  }
  this.getTags = () => {
    if( ! this.tags) {
      this.tags = data.TagList.reduce((tagObj, mapEntry) => {
        var json = `{ "${mapEntry.Key}": "${mapEntry.Value}" }`;
        var obj = JSON.parse(json);
        return Object.assign(tagObj, obj);
      }, {});
    }
    return this.tags;
  }
  this.getEndpointAddress = () => {
    return data.Endpoint.Address;
  }
  this.getLandscape = () => {
    return this.getTags().Landscape;
  }
  this.isKualiDatabase = () => {
    if(this.getTags().Service != 'research-administration') return false;
    if(this.getTags().Function != 'kuali') return false;
    if(this.getLandscape() == undefined) return false;
    return true;
  }
  this.getID = () => {
    return data.DBInstanceIdentifier;
  }
  this.getArn = () => {
    return data.DBInstanceArn;
  }
  this.getJSON = () => {
    return JSON.stringify(data, null, 2);
  }
};

const find = function(AWS, dbArn, callback) {
  var rds = new AWS.RDS();
  var id = dbArn.split(":").pop();
  rds.describeDBInstances({ DBInstanceIdentifier: id}, function(err, data) {
    var db = null;
    if ( ! err) {
      var db = new Database(data.DBInstances[0]);
    }
    callback(err, db);
  });
};

const loadDb = function(dbdata) {
  return new Database(dbdata);
};

module.exports = function() {
  this.find = find;
  this.load = loadDb;
}
