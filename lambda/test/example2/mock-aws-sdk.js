
var delay = 1;
module.exports = {
  ELBv2: function() {
    this.modifyLoadBalancerAttributes = (params, callback) => {
      setTimeout(() => {
        callback(null, 'Calling back from ELBv2.modifyLoadBalancerAttributes');
      }, delay * 1000);
    }
  },
  WAFV2: function() {
    this.deleteLoggingConfiguration = (params, callback) => {
      setTimeout(() => {
        callback(null, 'Calling back from WAFV2.deleteLoggingConfiguration');
      }, delay * 1000);
    }
  },
  S3: function() {
    this.deleteObject = (params, callback) => {
      setTimeout(() => {
        callback(null, {msg: 'Calling back from S3.deleteObject'});
        // callback({name: 'myerror', message:'oops!', stack: 'stacktrace...'}, {msg: 'Calling back from S3.deleteObject'});
      }, delay * 1000);
    },
    this.listObjects = (params, callback) => {
      setTimeout(() => {
        callback(null, {
          msg: 'Calling back from S3.listObjects', 
          Contents: [{Key:"bucket item 1"}, {Key:"bucket item 2"}, {Key:"bucket item 3"}]
        });
      }, delay * 1000);
    }
  }
};