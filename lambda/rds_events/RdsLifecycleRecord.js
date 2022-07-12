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

  /**
   * Determine if a bucket object exists. Will return "found" upon success.
   * @param {} callback 
   */
  this.find = (state, callback) => {
    const key = `${Folders.getByState(state)}/${rdsId}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`Searching for rds db lifecycle record: ${s3path}...`);
    const params = {
      Bucket: env.BUCKET_NAME, 
      Key: key
    };
    s3.headObject(params, function (err, data) {  
      if (err && err.name === 'NotFound') {
        console.log('Not found'); 
        callback(null, null)
      } 
      else if (err) {
        callback(err, null);
      }
      else {  
        callback(null, "found");
      }
    });
  }

  /**
   * Get the content of a file object expected to exist in s3 by name of a prior or existing rds instance id.
   * The file contains the details of the rds object as returned by the rds.describeDBInstances api method.
   * @param {*} callback 
   */
  this.load = (state, callback) => {
    const key = `${Folders.getByState(state)}/${rdsId}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`Loading the rds db lifecycle record: ${s3path}...`);
    const params = {
      Bucket: env.BUCKET_NAME, 
      Key: key
    };
    
    this.find(state, (err, data) => {
      if(err) {
        callback(err, null);
      }
      else if(data == 'found') {
        s3.getObject(params, (err, data) => {
          if(err) {
            callback(err, null);
          }
          else {
            callback(null, data.Body.toString('utf-8'));
          }
        });        
      }
      else {
        callback(null, null);
      }
    });
  };

  /**
   * Save the json comprising an rds intance details as an s3 file named according to the endpoint address.
   * @param {*} callback 
   */
  this.persist = (callback) => {
    const key = `${Folders.CREATED}/${rdsId}`
    const s3path = `${env.BUCKET_NAME}/${key}`
    console.log(`Persisting rds db lifecycle record: ${s3path}...`);
    const params = {
      Body: rdsDb.getJSON(), 
      Bucket: env.BUCKET_NAME, 
      Key: key
    };
    s3.putObject(params, function(err, data) {
      if(err) {
        console.error(`Failed to persist db lifecycle record to: ${s3path}`);
      }
      else {
        console.log(`Succeeded persisting db lifecycle record to: ${s3path}`);
        console.log(data);
      }
      callback(err, data);
    });
  }

  /**
   * Moving rds lifecycle records from one lifecycle state to another means moving the related s3 object from
   * one location to another. The move is accomplished in two steps: 1) Copy to new location 2) Delete from original location.
   * @param {*} fromState 
   * @param {*} toState 
   * @param {*} callback 
   */
  this.move = (fromState, toState, callback) => {
    var copyParms = {
      Bucket: env.BUCKET_NAME, 
      CopySource: `${env.BUCKET_NAME}/${Folders.getByState(fromState)}/${rdsId}`, 
      Key: `${Folders.getByState(toState)}/${rdsId}`
    };
    if(toState == 'final') {
      copyParms.Key += `_${Timestamp()}`;
    }

    s3.copyObject(copyParms, function(err, data) {
      if(err) {
        console.error(`Failed to copy ${copyParms.Bucket}/${copyParms.CopySource} to ${copyParms.Bucket}/${copyParms.Key}`);
        callback(err, data);
      }
      else {
        console.log(`Copy success: ${copyParms.Bucket}/${copyParms.CopySource} to ${copyParms.Bucket}/${copyParms.Key}`);
        var deleteParms = {
          Bucket: `${env.BUCKET_NAME}`, 
          Key: `${Folders.getByState(fromState)}/${rdsId}`
        }
        s3.deleteObject(deleteParms, function(err, data) {
          if(err) {
            console.error(`Failed to delete ${deleteParms.Bucket}/${deleteParms.Key}`)
          }
          else {
            console.log(`Delete success: ${deleteParms.Bucket}/${deleteParms.Key}`);
          }
          callback(err, data);
        });
      }
    });
  }
}