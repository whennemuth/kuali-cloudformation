/**
 * Create mock objects that simulate those that would be carried by an http request to a lambda function
 * from a lambda-backed cloudformation custom resource.
 * SEE: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-lambda.html
 *      https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/crpg-ref-requests.html
 * 
 * The triggered lambda code is passed an event object that contains the various data provided by the custom
 * resource, including a ResourceProperties collection.
 * Each argument passed to this javascript file corresponds to a field that is expected in the ResourceProperties
 * object. So a mock event object with a ResourcePropeties field is passed to the event handler.
 */
var toggler = require('./toggle_alb_logging.js');
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
