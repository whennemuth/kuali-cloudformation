var AWS = require("aws-sdk");

switch (process.env.MODE) {
  case 'mocked':
    var response = {
      SUCCESS: 'SUCCESS',
      FAILURE: 'FAILURE',
      send: (event, context, status, data) => {
        console.log('Sending ' + status + ' response, data: ' + JSON.stringify(data));
      }
    }; break;
  case 'unmocked':
    var response = require('cfn-response'); break;
  default:
    var response = require('cfn-response'); break;
}

exports.handler = function (event, context) {
  try {
    var s3 = new AWS.S3();
    switch (event.RequestType) {
      case "Create":
        console.log(event.ResourceProperties);
        var bucketname = event.ResourceProperties.BucketName;
        var key = `${event.ResourceProperties.BucketPath}/${event.ResourceProperties.SecurityGroupGroupIds[0]}`;
        s3.getObject({ Bucket: bucketname, Key: key }, function (err, data) {
          if (err) {
            console.log(`ERROR: Cannot list bucket objects: ${err}`);
            console.log(err, err.stack);
          }
          else if (!data || !data.Body) {
            console.log(`WARNING: No content in ${bucketname}/${key}`)
          }
          else {
            // console.log(JSON.stringify(JSON.parse(data.Body.toString('utf-8'))), null, "\t");
            console.log(data.Body.toString('utf-8').replace("\\\\n", "\\n"));
          }
        });
        response.send(event, context, response.SUCCESS, { Value: "Put json here" });
        break;
      case "Delete":
        response.send(event, context, response.SUCCESS, { Value: "Put json here" });
        break;
      default:
        response.send(event, context, response.SUCCESS, { Value: "Put json here" });
        break;
    }
  }
  catch (e) {
    console.error(e);
    response.send(event, context, response.FAILURE, { Value: { error: { name: e.name, message: e.message } } });
  }
}