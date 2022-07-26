/**
 * This module represents a single rds database.
 */

/**
 * This function represents a decorator for the raw details of a single rds database.
 * @param {*} data The decorated rds data, obtained using the RDS.describeDBInstances sdk method.
 */
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
  this.getBaseline = () => {
    var baseline = this.getTags().Baseline;
    if( ! baseline) {
      baseline = this.getLandscape();
    }
    return baseline;
  }
  this.getReplacesId = () => {
    return this.getTags().Replaces;
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
  this.getShortJSON = () => {
    return JSON.stringify({
      DBInstanceIdentifier: data.DBInstanceIdentifier,
      DBInstanceArn: data.DBInstanceArn,
      DBEndpoint: data.Endpoint.Address,
      VpcSecurityGroups: JSON.stringify(data.VpcSecurityGroups),
      Tags: JSON.stringify(this.getTags())
    }, null, 2);
  }
  this.hasSameBaselineAs = otherdb => {
    return this.getBaseline() == otherdb.getBaseline();
  }
  this.hasSameLandscapeAs = otherdb => {
    return this.getLandscape() == otherdb.getLandscape();
  }
  this.getVpcSecurityGroups = () => {
    if (data.VpcSecurityGroups && data.VpcSecurityGroups[0]) {
      return data.VpcSecurityGroups;
    }
    return [];
  }
  /**
   * More than one vpc security group is not anticipated.
   * @returns The first vpc security group id found for the rds instance
   */
  this.getFirstSecurityGroupId = () => {
    return this.getVpcSecurityGroups().length == 0 ? undefined : this.getVpcSecurityGroups()[0].VpcSecurityGroupId;
  }
};

/**
 * This function performs an async aws api lookup for a details of an rds database and returns the decorated result.
 * @param {*} AWS An aws sdk object.
 * @param {*} dbArn The arn of the rds db to lookup.
 * @returns A promise of the decorated rds db details.
 */
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

/**
 * This function returns a decorator object for an rds database.
 * @param {*} dbdata The rds db details to decorate.
 * @returns Decorator for the rds db details.
 */
const loadDb = function(dbdata) {
  return new Database(dbdata);
};

module.exports = function() {
  this.find = find;
  this.load = loadDb;
}
