var scheduler = require('./ResourceProcessor.js');
var event = '';
if(process.argv.length == 3) {
  event = JSON.parse(process.argv[2]);
}
scheduler.handler(event);
