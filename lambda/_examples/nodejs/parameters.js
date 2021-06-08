var AWS = require('aws-sdk');


module.exports = async (cfnEvent, isEligibleTask, callback) => {

  const parms = {
    resource: cfnEvent.ResourceProperties.resource,
    target: cfnEvent.ResourceProperties.target,
    albArn: process.env.LOAD_BALANCER_ARN,
    webAclArn: process.env.WEBACL_ARN,
    albBucketName: process.env.ALB_BUCKET_NAME,
    wafBucketName: process.env.WAF_BUCKET_NAME,
    athenaBucketName: process.env.ATHENA_BUCKET_NAME,
    errors: []
  };

  try {
    var resourcegroupstaggingapi = new AWS.ResourceGroupsTaggingAPI({apiVersion: '2017-01-26'});

    // Promisify the use of callbacks in the getResources function so they can be made synchronous with await.
    const getResourcesPromise = (params) => {
      return new Promise((resolve, reject) => {
        resourcegroupstaggingapi.getResources(params, function(err, data) {
          if (err) {
            reject(err);
          }
          else {
            resolve(data);
          }
        });
      })
    };
    

    // Looks up the arns for a resource like alb or waf, assuming they are tagged as kuali resources.
    this.setArn = async (resource, resourceType, landscape, setValue) => {
      if( ! landscape ) {
        return false;
      }
      var tagFilters = [
        { Key: 'Landscape', Values: [ process.env.LANDSCAPE ] },
        { Key: 'Function', Values: [ 'Kuali' ] },
        { Key: 'Service', Values: [ 'research-administration' ] }      
      ];
      try {  
        console.log(`Looking up ${resource} arn for ${landscape} landcape...`);
        var data = await getResourcesPromise({
          ResourceTypeFilters: [ resourceType ],
          TagFilters: tagFilters
        });
        if(data && data.ResourceTagMappingList && data.ResourceTagMappingList.length > 0) {
          console.log(data.ResourceTagMappingList[0].ResourceARN);
          setValue(data.ResourceTagMappingList[0].ResourceARN);
        }
        else {
          console.log(`${resource} not found!`);
        }        
      }
      catch(err) {
        console.log(err, err.stack); 
      }  
    }

    // Set the arn of the ALB
    if( ! parms.albArn && isEligibleTask(parms.resource, parms.target, {resource:'alb', target:'logging'}) ) {
      await this.setArn(
        'alb', 
        'elasticloadbalancing', 
        process.env.LANDSCAPE, 
        (arn) => parms.albArn = arn );
    } 

    // Set the arn of the WAF
    if( ! parms.webAclArn && isEligibleTask(parms.resource, parms.target, {resource:'waf', target:'logging'}) ) {
      await this.setArn(
        'waf', 
        'wafv2', 
        process.env.LANDSCAPE,
        (arn) => parms.webAclArn = arn );
    }
  }
  catch(e) {
    parms.errors.push(e);
  }

  callback(parms);
}
