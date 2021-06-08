var cleanup = require('./cleanup.js');
var args = process.argv.slice(2);
var props = eval('(' + args[0] +')');
var mockEvent = {
  ResourceProperties: {},
  RequestType: 'Delete'
}
Object.assign(mockEvent.ResourceProperties, props);
cleanup.handler(mockEvent, null);
