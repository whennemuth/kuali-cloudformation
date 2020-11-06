/**
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 * 
 * NOTE: You won't need this module if you are supplying your code as an inline yaml segment with the "ZipFile" property.
 * This is because Cloudformation will automatically include it for you. However, if you are packaging you own code
 * and supplying it through the "S3Bucket" and "S3key" properties, you have to supply your own response code or this 
 * module in the zipped package that you create.
 * 
 * See: 
 *   https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-lambda-function-code-cfnresponsemodule.html
 *   https://docs.aws.amazon.com/lambda/latest/dg/nodejs-package.html
 * 
 */

exports.SUCCESS = "SUCCESS";
exports.FAILED = "FAILED";
 
exports.send = function(event, context, responseStatus, responseData, physicalResourceId, noEcho) {
 
    var responseBody = JSON.stringify({
        Status: responseStatus,
        Reason: "See the details in CloudWatch Log Stream: " + context.logStreamName,
        PhysicalResourceId: physicalResourceId || context.logStreamName,
        StackId: event.StackId,
        RequestId: event.RequestId,
        LogicalResourceId: event.LogicalResourceId,
        NoEcho: noEcho || false,
        Data: responseData
    });
 
    console.log("Response body:\n", responseBody);
 
    var https = require("https");
    var url = require("url");
 
    var parsedUrl = url.parse(event.ResponseURL);
    var options = {
        hostname: parsedUrl.hostname,
        port: 443,
        path: parsedUrl.path,
        method: "PUT",
        headers: {
            "content-type": "",
            "content-length": responseBody.length
        }
    };
 
    var request = https.request(options, function(response) {
        console.log("Status code: " + response.statusCode);
        console.log("Status message: " + response.statusMessage);
        context.done();
    });
 
    request.on("error", function(error) {
        console.log("send(..) failed executing https.request(..): " + error);
        context.done();
    });
 
    request.write(responseBody);
    request.end();
}