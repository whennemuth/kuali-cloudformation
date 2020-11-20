var toggler = require('./toggle_waf_logging.js');
var args = process.argv.slice(2);
var resourceProps = {};
args.forEach(prop => {
  Object.assign(resourceProps, eval('(' + prop +')'));
});
var mockEvent = {
  ResourceProperties: resourceProps,
  RequestType: 'Delete'
}
toggler.handler(mockEvent, null);
