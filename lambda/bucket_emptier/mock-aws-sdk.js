
var delay = 1;
module.exports = {
  S3: function() {
    this.counter = 1,
    this.tokens = [ "token1", "token2", "token3" ],
    this.listBuckets = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          Buckets: [
            {
            CreationDate: '<Date Representation>', 
            Name: "bucket1"
            }, 
            {
            CreationDate: '<Date Representation>', 
            Name: "bucket2"
            }, 
            {
            CreationDate: '<Date Representation>', 
            Name: "bucket3"
            }
          ], 
          Owner: {
            DisplayName: "Warren", 
            ID: "examplee7a2f25102679df27bb0ae12b3f85be6f290b936c4393484be31"
          }
        });
      }, delay * 1000);
    },
    this.listObjectsV2 = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          msg: 'Calling back from S3.listObjects', 
          Contents: this.tokens.length == 1 ? [
            {Key: `bucket item ${this.counter++}`}
          ] : [
            {Key: `bucket item ${this.counter++}`}, 
            {Key: `bucket item ${this.counter++}`}
          ],
          IsTruncated: this.tokens.length > 1, 
          KeyCount: this.tokens.length == 0 ? 1 : params.MaxKeys, 
          MaxKeys: params.MaxKeys, 
          Name: "examplebucket", 
          NextContinuationToken: this.tokens.shift(), 
          Prefix: ""      
        });
      }, delay * 1000);
    },
    this.deleteObjects = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          Deleted: this.tokens.length == 0 ? [
            {
              DeleteMarker: true, 
              DeleteMarkerVersionId: "A._w1z6EFiCF5uhtQMDal9JDkID9tQ7F", 
              Key: `bucket item ${this.counter}`
            }            
          ] : [
            {
              DeleteMarker: true, 
              DeleteMarkerVersionId: "A._w1z6EFiCF5uhtQMDal9JDkID9tQ7F", 
              Key: `bucket item ${this.counter-1}`
            }, 
              {
              DeleteMarker: true, 
              DeleteMarkerVersionId: "iOd_ORxhkKe_e8G8_oSGxt2PjsCZKlkt", 
              Key: `bucket item ${this.counter}`
            }
          ]     
        });
        // callback({name: 'myerror', message:'oops!', stack: 'stacktrace...'}, {msg: 'Calling back from S3.deleteObject'});
      }, delay * 1000);
    }
  }
};