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
  this.hasSameLandscapeAs = otherdb => {
    return this.getLandscape() == otherdb.getLandscape();
  }
};

const find = function(AWS, dbArn) {
  var rds = new AWS.RDS();
  var id = dbArn.split(":").pop();

  return new Promise(
    (resolve) => {
      try {
        resolve((async () =>{
          var data = null;
          await rds.describeDBInstances({ DBInstanceIdentifier: id }).promise()
            .then(d => { 
              data = d; 
            })
            .catch(err => { 
              throw(err); 
            });
          return new Database(data.DBInstances[0])      
        })());
      }
      catch (err) {
        throw(err);
      }
    }
  );
};

const loadDb = function(dbdata) {
  return new Database(dbdata);
};

module.exports = function() {
  this.find = find;
  this.load = loadDb;
}
