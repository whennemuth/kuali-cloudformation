var wafAdjust = require('./index.js');

var myEvent = {
  ResourceProperties: {
    us_only: true,
    test_task: true
  },
  RequestType: 'Create'
}

wafAdjust.handler(myEvent, null);
