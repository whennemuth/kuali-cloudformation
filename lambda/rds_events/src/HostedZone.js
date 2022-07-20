const KualiHostedZone = function(hsdata, rrdata) {
  this.exists = () => {
    return hsdata ? true : false;
  }
  this.getData = () => {
    return hsdata;
  }
  this.getTags = () => {
    if( ! this.tags) {
      this.tags = hsdata.TagList.reduce((tagObj, mapEntry) => {
        var json = `{ "${mapEntry.Key}": "${mapEntry.Value}" }`;
        var obj = JSON.parse(json);
        return Object.assign(tagObj, obj);
      }, {});
    }
    return this.tags;
  }
  this.getName = () => {
    var name = hsdata.HostedZone.Name;
    if(name.endsWith('.')) {
      name = name.replace(/\.$/, '');
    }
    return name;
  }
  this.getDbRecordForLandscape = landscape => {
    return rrdata.ResourceRecordSets.find(element => {
      return element.Name.startsWith(`${landscape}.db.`)
    });
  }
  this.updateDbResourceRecordSetTarget = async (AWS, dbRec, newTarget) => {
    return new Promise(
      (resolve) => {
        try {
          var newDbRec = {};
          Object.assign(newDbRec, dbRec);
          newDbRec.ResourceRecords[0].Value = newTarget;
          var params = {
            HostedZoneId: hsdata.HostedZone.Id,
            ChangeBatch: {
              Changes: [
                {
                  Action: 'UPSERT',
                  ResourceRecordSet: newDbRec
                } 
              ],
              Comment: `Changing ${dbRec.Name} resource record target value.`
            }
          };

          resolve((async () => {
            var data = null;
            var route53 = new AWS.Route53();
            await route53.changeResourceRecordSets(params).promise()
              .then(d => {
                data = d;
              })
              .catch(err => {
                throw(err);
              });
            return data;
          })());
        }
        catch(err) {
          throw(err);
        }
      }
    );
  }
}

exports.lookup = function(AWS, hostedZoneName) {
  var route53 = new AWS.Route53();

  return new Promise(
    (resolve) => {
      try {
        resolve((async () => {

          // 1) Get a list of all hosted zones
          var hostedZones = null;
          await route53.listHostedZones({}).promise()
            .then(data => {
              hostedZones = data.HostedZones;
            })
            .catch(err => {
              throw(err);
            });

          // 2) Fish through the list for a hosted zone with a matching name
          var hostedzone = null;
          hostedZones.forEach(h => {
            if(h.Name == hostedZoneName || h.Name == `${hostedZoneName}.`) {
              hostedzone = h;
            }
          });
          if( ! hostedzone) {
            console.log(`No such hosted zone: ${hostedZoneName}`);
            return new KualiHostedZone(null, null);
          }

          // 3) With a matching hosted zone name, perform a lookup for the ID of the hosted zone
          var hostedZoneData = null;
          await route53.getHostedZone({ Id: hostedzone.Id }).promise()
            .then(h => {
              hostedZoneData = h;
            })
            .catch(err => {
              throw(err);
            });

          // 4) Make a separate lookup for the resource recordsets in the hosted zone.
          var resourceRecordsets = null;
          await route53.listResourceRecordSets({ HostedZoneId: hostedzone.Id }).promise()
            .then(r => {
              resourceRecordsets = r;
            })
            .catch(err => {
              throw(err);
            });

          // 5) Return the KualiHostedZone object
          return new KualiHostedZone(hostedZoneData, resourceRecordsets);
        })());
      }
      catch(err) {
        throw(err);
      }
    }
  );
}

exports.load = function(hostedZoneData) {
  return new KualiHostedZone(hostedZoneData);
}

