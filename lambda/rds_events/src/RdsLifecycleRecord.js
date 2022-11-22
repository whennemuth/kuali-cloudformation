/**
 * A lifecycle record tracks the state of an rds database as an s3 object.
 * The s3 object is named after the rds database id and its s3 path indicates its state:
 * CREATED: This indicates the rds database exists right now.
 * PENDING: This indicates the rds database has been deleted, but no replacement (determined by landscape) database has appeared.
 * FINAL: This indicates the rds database has been deleted, and the related route53 CNAME record has been up updated to
 * reflect the endpoint address of a new rds database that has taken its place.
 */
const date = require('date-and-time');

const Folders = new function() {
  this.MAIN = 'rds-lifecycle-events';
  this.CREATED = `${this.MAIN}/created`;
  this.PENDING = `${this.MAIN}/deleted/pending`;
  this.FINAL = `${this.MAIN}/deleted/final`;
  this.getByState = state => {
    switch(state.toLowerCase()) {
      case 'created': return this.CREATED; break;
      case 'pending': return this.PENDING; break;
      case 'final': return this.FINAL; break;
    }
  }
};

const Timestamp = () => {
  return date.format(new Date(),'YYYY-MM-DD-HH.mm.ss');
};

module.exports = function(AWS, rdsParm) {
  const env = process.env;
  const s3 = new AWS.S3();

  if(typeof rdsParm === 'string') {
    var rdsArn = rdsParm;
    var rdsId = rdsArn.split(':').pop();
  }
  else {
    var rdsDb = rdsParm;
    var rdsId = rdsDb.getID();
  }

  this.getRdsId = (state) => {
    if(state == 'pending') {
      if(rdsDb) {
        return rdsDb.getReplacesId() || rdsId;
      }
    }
    return rdsId;
  }

  /**
   * Determine if a bucket object exists. Will return "found" upon success.
   */
  this.find = (state) => {
    const key = `${Folders.getByState(state)}/${this.getRdsId(state)}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`Searching for rds db lifecycle record: ${s3path}...`);
    const params = {
      Bucket: env.BUCKET_NAME, 
      Key: key
    };

    return new Promise(
      (resolve) => {
        try {
          resolve((async () => {
            var retval = null;
            await s3.headObject(params).promise()
              .then(data => {
                retval = data ? 'found' : 'NotFound';
              })
              .catch(err => {
                if(err.name === 'NotFound') {
                  retval = null;
                }
                else {
                  throw(err);
                }                
              });
            return retval;
          })());
        }
        catch(err) {          
          throw(err);
        }
      }
    );
  }

  /**
   * Get the content of a file object expected to exist in s3 by name of a prior or existing rds instance id.
   * The file contains the details of the rds object as returned by the rds.describeDBInstances api method.
   */
  this.load = (state) => {
    const key = `${Folders.getByState(state)}/${this.getRdsId(state)}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`About to locate and load the rds db lifecycle record: ${s3path}...`);
    const params = {
      Bucket: env.BUCKET_NAME, 
      Key: key
    };

    return new Promise(
      (resolve) => {
        try {
          resolve(
            (async () => {
              var searchResult = await this.find(state);
              if(searchResult == 'found') {
                console.log(`Found rds db lifecycle record ${s3path}, loading...`);
                var data = null;
                await s3.getObject(params).promise()
                  .then(d => {
                    data = d;
                  })
                  .catch(err => {
                    throw(err);
                  })
                return data.Body.toString('utf-8');
              }
              else {
                console.log(`No such rds db lifecycle record ${s3path}!`);
                return null;
              }
            })()
          );
        }
        catch(err) {
          throw(err);
        }
      }
    );
  };

  /**
   * Save the json comprising an rds instance details as an s3 file named according to the baseline landscape of the rds instance.
   */
  this.persist = () => {
    const key = `${Folders.CREATED}/${rdsId}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`Persisting rds db lifecycle record: ${s3path}...`);
    const params = {
      Body: rdsDb.getJSON(), 
      Bucket: env.BUCKET_NAME, 
      Key: key
    };

    return new Promise(
      (resolve) => {
        try {
          resolve(
            (async () => {
              var data = null;
              await s3.putObject(params).promise()
                .then(d => {
                  data  = d;
                  console.log(`Succeeded persisting db lifecycle record to: ${s3path}`);
                  console.log(data);
                })
                .catch(err => {
                  console.error(`Failed to persist db lifecycle record to: ${s3path}`);
                  throw(err);
                });
              return data;     
            })()
          );
        }
        catch(err) {
          console.error(`Failed to persist db lifecycle record to: ${s3path}`);
          throw(err);
        }
      }
    );
  }

  /**
   * Moving rds lifecycle records from one lifecycle state to another means moving the related s3 object from
   * one location to another. The move is accomplished in two steps: 1) Copy to new location 2) Delete from original location.
   * @param {*} fromState 
   * @param {*} toState 
   */
  this.move = (fromState, toState) => {
    var copyParms = {
      Bucket: env.BUCKET_NAME, 
      CopySource: `${env.BUCKET_NAME}/${Folders.getByState(fromState)}/${rdsId}`, 
      Key: `${Folders.getByState(toState)}/${rdsId}`
    };
    if(toState == 'final') {
      copyParms.Key += `_${Timestamp()}`;
    }
    var deleteParms = {
      Bucket: `${env.BUCKET_NAME}`, 
      Key: `${Folders.getByState(fromState)}/${rdsId}`
    }

    return new Promise(
      (resolve) => {
        try {
          resolve((async () => {

            // 1) Copy the s3 object to another location.
            var copyData = null;
            await s3.copyObject(copyParms).promise()
              .then(d => {
                copyData = d;
                console.log(`Copy success: ${copyParms.Bucket}/${copyParms.CopySource} to ${copyParms.Bucket}/${copyParms.Key}`);
              })
              .catch(err => {
                console.error(`Failed to copy ${copyParms.Bucket}/${copyParms.CopySource} to ${copyParms.Bucket}/${copyParms.Key}`);
                throw(err);
              });

            // 2) Delete the s3 object from the original location.
            var deleteData = null;
            await s3.deleteObject(deleteParms).promise()
              .then(d => {
                deleteData = d;
                console.log(`Delete success: ${deleteParms.Bucket}/${deleteParms.Key}`);
              })
              .catch(err => {
                console.error(`Failed to delete ${deleteParms.Bucket}/${deleteParms.Key}`);
                throw(err);
              });

              return {
                copyResult: copyData,
                deleteResult: deleteData
              }
          })())          
        }
        catch(err) {
          console.error(`Failed to move ${copyParms.Bucket}/${copyParms.CopySource} to ${copyParms.Bucket}/${copyParms.Key}`);
          throw(err);          
        }
      }
    );
  }
}