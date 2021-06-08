const ResourceDecoratorForRDS = require("./ResourceDecoratorForRDS");
const ResourceDecoratorForEC2 = require("./ResourceDecoratorForEC2");
const ResourceDecoratorForECS = require("./ResourceDecoratorForECS");

module.exports = function(AWS) {
  this.AWS = AWS;
  this.getResource = (basicResource) => {
    var resource = {};
    switch(basicResource.getType()) {
      case 'ec2':
        resource = new ResourceDecoratorForEC2(basicResource, this.AWS);
        break;
      case 'rds':
        resource = new ResourceDecoratorForRDS(basicResource, this.AWS);
        break;
      case 'ecs':
        resource = new ResourceDecoratorForECS(basicResource, this.AWS);
        break;
    }
    return resource;
  }
}