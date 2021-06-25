
const Resource = require('./Resource');
const ResourceFactory = require('./ResourceFactory');

/**
 * This function represents a full list of aws resources that are tagged with specified keys. To be included in the list, 
 * a resource must have each of the specified tag keys. Among the tags are expected to be those that have cron expressions 
 * as values that indicate the scheduling for the startup and shutdown of the resources. Functionality includes querying 
 * the aws account for the resources and a recursing subfunction into which can be injected a custom function to execute 
 * against each resource (probably the shutdown or startup call).
 * 
 * @param {aws-sdk} AWS - Need this library for api calls.
 * @param {Object} tagsOfInterest - Tags that must be found on the resource for shutdown/startup and its scheduling.
 */
exports.load = function(AWS, tagsOfInterest, callback) {

  this.resources = [];

  try {

    // Construct parameters for the tagging api call.
    
    var params = {
      ResourceTypeFilters: [ 'rds:db', 'ec2:instance' ],
      TagFilters: [ ]
    };

    if(process.env.DefaultTimeZone) {
      console.log(`It looks like you are testing. Resources without timezone tags are not going to be filtered off
                  as usual and will get "${process.env.DefaultTimeZone}" as a timezone.`.replace(/\s{2,}/g, ' '));
    }
    else {
      params.TagFilters.push({ Key: tagsOfInterest.timezoneTag });
    }

    // Make the tagging api call.
    var resourcegroupstaggingapi = new AWS.ResourceGroupsTaggingAPI({apiVersion: '2017-01-26'});
    console.log("Calling resource tagging api...");
    resourcegroupstaggingapi.getResources(params, (err, data) => {
      if(err) {
        console.log(err, err.stack);
        callback(err);
      }
      else {
        var factory = new ResourceFactory(AWS);
        if(data && data.ResourceTagMappingList) {
          // console.log("Resources found: ");
          // console.log(JSON.stringify(data, null, 2));
          data.ResourceTagMappingList.forEach(tagsAndArnObj => {
            // Instantiate an object that represents a resource that "knows" only about its tags and arn
            var basicResource = new Resource(tagsAndArnObj, tagsOfInterest);
            if(basicResource.getStartCron() || basicResource.getStopCron() || basicResource.getRebootCron()) {
              // Tagging indicates a cron schedule, so wrap the object with a factory produced decorator that "knows" 
              // how to perform actions specific to that resource and add it to the collection.
              let resource = factory.getResource(basicResource);
              if(basicResource.getTimeZone()) {
                this.resources.push(resource);
              }
              else if(process.env.DefaultTimeZone) {
                resource.setTimeZone(process.env.DefaultTimeZone);
                this.resources.push(resource);
              }
              else {                
                console.warn(`Resource ${resource.getId()} is missing a "${tagsOfInterest.timezoneTag}" tag.`);
              }              
            }              
          });
        }
        else {
          console.warn("No resources idenfified by tag for shutdown/startup");
        }
      }

      callback(this);
    });
  }
  catch(e) {
    e.stack ? console.error(e, e.stack) : console.error(e);
    callback(e);
  }

  
  /**
   * Process each resource in the array. The resources array is not being iterated. Instead resources
   * are removed and processed one at a time by recursive callback until the resources array is empty.
   * 
   * @param {Function} task - A function (task) to execute for each resource (like stopping or starting the resource)
   * @param {Function} callback - A function to execute once the task function is executed.
   */
  this.processNext = (task, callback) => {
    var resource = this.resources.shift();
    if(resource) {
      task(resource, () => {
        this.processNext(task, callback);
      });
    }
    else {
      callback();
    }
  }
};