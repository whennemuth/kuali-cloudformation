switch(process.env.DEBUG_MODE) {
  case 'local_mocked':
    var AWS = require('./mock-aws-sdk');
    var response = require('./mock-cfn-response');
    break;
  case 'local_unmocked':
    var AWS = require('aws-sdk');
    var response = require('./mock-cfn-response');
    break;
  default:
    var AWS = require('aws-sdk');
    var response = require('cfn-response');
    break;
}

/**
 * Determine if the bucket specified by name exists and return the result by callback.
 * @param {*} s3 
 * @param {*} bucketName 
 * @param {*} callback 
 */
const bucketExists = (s3, bucketName, callback) => {
  try {
    console.log(`Checking that s3 bucket "${bucketName}" exists...`);
    s3.headBucket({Bucket: bucketName}, function(err, data) {
      try {
        if(err) {
          switch(err.statusCode) {
            case 404:
              console.log(`Bucket "${bucketName}" does not exist.`);
              callback(null, false);
              break;
            case 403:
              console.log(`Bucket "${bucketName}" may exist but access is forbidden.`);
              console.log('Is this bucket in the right account?');
              console.log('Are you running with a role that has a policy with sufficient actions or resource expression that matches the bucket arn?');
              callback(null, false);
              break;
            default:
              console.log(`Bucket "${bucketName}" existence cannot be verified.`);                
              callback(err, null);
              break;
          }
        }
        else {
          console.log(`Bucket "${bucketName}" exists.`);
          callback(null, true);
        }
      }
      catch(e) {
        console.log(`Error getting head bucket: "${bucketName}"!`);
        callback(e, null);
      }
    });
  }
  catch(e) {
    console.log(`Error checking s3 bucket "${bucketName}"`);
    callback(e, null);
  }
};


/**
 * Make a call to list the objects in a bucket and delete the objects returned. Not all contents of the bucket will 
 * be returned by the call to list them if the total bucket population exceeds the MaxKeys numeric value. This means 
 * potentially multiple calls until all bucket contents are deleted. 
 * @param {*} s3 
 * @param {*} listParms 
 * @param {*} callback 
 */
const deleteS3Objects = (s3, listParms, callback) => {
  try {
    s3.listObjectsV2(listParms, function(err, listData) {
      try {
        if(err) {
          callback(err, listData);
        }
        else {

          var deleteParms = {
            Bucket: listParms.Bucket, 
            Delete: {
              Objects: listData.Contents.map(item => {
                return {Key: item.Key};
              }),
              Quiet: false
            }
          };
          
          if(deleteParms.Delete.Objects.length > 0) {
            console.log(`Deleting ${deleteParms.Delete.Objects.length} items from ${listParms.Bucket}...`);
            s3.deleteObjects(deleteParms, function(err, deleteData) {
              if(err) {
                callback(err, deleteData);
              }
              else {
                deleted += deleteData.Deleted.length;
                console.log(`${deleteData.Deleted.length} items deleted (total: ${deleted}) from ${listParms.Bucket}`);
                if(listData.IsTruncated) {
                  /** There are more contents, retrievable later by another s3.listObjectsV2 call using the token returned by the last call. */
                  deleteS3Objects(s3, Object.assign(listParms, {ContinuationToken: listData.NextContinuationToken}), callback);
                }
                else {
                  /** The last of the bucket content was just deleted, the bucket should now be empty. */
                  callback(null, 'EMPTIED');
                }    
              }
            });          
          }
          else {
            callback(null, 'EMPTIED');
          }
        }
      }
      catch(e) {
        callback(e, null);
      }
    });
  }
  catch(e) {
    console.log(`Error deleting objects from ${listParms.Bucket}`);
    callback(e, null);
  }
};

var deleted = 0;
const emptyBucket = (bucketName, maxKeys, callback) => {
  try {
    var s3 = new AWS.S3();
    bucketExists(s3, bucketName, (err, exists) => {
      if(err) {
        callback(err, null);
      }
      else {
        if(exists) {
          deleteS3Objects(s3, {Bucket: bucketName, MaxKeys: maxKeys}, (err, data) => {
            callback(err, data);
          });
        }
        else {
          callback(null, 'UNAVAILABLE');
        }
      }
    });
  }
  catch(e) {
    callback(e, null);
  }
}

const sendErrorResponse = (event, context, err) => {
  try {
    err.stack ? console.log(err, err.stack) : console.log(err);
    var msg = err.name + ': ' + err.message;
    var bucketName = event.ResourceProperties.BucketName;
    if( ! bucketName) bucketName = 'unknown'
    response.send(event, context, response.FAILED, { Reply: `Failed to empty s3 bucket: "${bucketName}": ${msg}, (see cloudwatch logs for detail)` });
  }
  catch(e) {
    response.send(event, context, response.FAILED, { Reply: `Failed to empty s3 bucket, (see cloudwatch logs for detail)` });
  }
}


/**
 * Toggle logging for the alb and send a success response even if the alb cannot be verified or found.
 * Send a failure response only if an exception occurs.
 * @param {*} event 
 * @param {*} context 
 */
exports.handler = function (event, context) {
  try {
    if (/^delete$/i.test(event.RequestType)) {
      const bucketName = event.ResourceProperties.BucketName;
      var maxKeys = event.ResourceProperties.MaxKeys;
      if( ! maxKeys) maxKeys = 100;
      emptyBucket(bucketName, maxKeys, (err, result) => {
        if(err) {
          sendErrorResponse(event, context, err);
        }
        else {
          var responseCode = response.SUCCESS
          if(result == 'UNAVAILABLE') {
            var reply = `"${bucketName}" does not exist or is forbidden access.`;
            responseCode = response.FAILED
          }
          else if(deleted == 0) {
            var reply = `"${bucketName}" was already empty.`;
          }
          else {
            var reply = `"${bucketName}" emptied - ${deleted} objects deleted.`;
          }
          console.log(reply);
          response.send(event, context, responseCode, { Reply: reply });  
        } 
      })
    }
    else {
      console.log(`Stack operation is: ${event.RequestType}, cancelling lambda execution - emptying of s3 buckets does not apply...'`);
      response.send(event, context, response.SUCCESS, { Reply: 'skipped' });
    }
  }
  catch(e) {
    sendErrorResponse(event, context, e);
  }
}