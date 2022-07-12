const KualiHostedZone = function(hsdata, rrdata) {
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
  this.updateDbResourceRecordSetTarget = (AWS, dbRec, newTarget, callback) => {
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
    var route53 = new AWS.Route53();
    route53.changeResourceRecordSets(params, function(err, data) {
      callback(err, data);
    });
  }
}

exports.lookup = function(AWS, hostedZoneName, callback) {
  var route53 = new AWS.Route53();
  // 1) List hosted zones
  route53.listHostedZones({}, function(err, data) {
    if(err) {
      callback(err, err.stack);
    }
    else {
      data.HostedZones.forEach(hostedzone => {
        if(hostedzone.Name == hostedZoneName || hostedzone.Name == `${hostedZoneName}.`) {
          // 2) Get the hosted zone based of the list selection.
          route53.getHostedZone({ Id: hostedzone.Id }, (err, hsdata) => {
            if(err) {
              callback(err, hsdata);
            }
            else {
              // 3) Make a separate call to get the resource records of the hosted zone.
              route53.listResourceRecordSets({ HostedZoneId: hostedzone.Id }, (err, rrdata) => {
                var khz = null;
                if(err) {
                  callback(err, rrdata);
                }
                else {
                  khz = new KualiHostedZone(hsdata, rrdata);
                  callback(err, khz);
                }                
              })
            }
          })
        }
      });
    }
  });
}

exports.load = function(hostedZoneData) {
  return new KualiHostedZone(hostedZoneData);
}

