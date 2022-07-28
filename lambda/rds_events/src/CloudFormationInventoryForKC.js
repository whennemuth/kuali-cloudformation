const CloudFormationInventory = require('./CloudFormationInventory');

module.exports = function(AWS, baseline) {
  const parms = {
    AWS: AWS,
    RdsVpcSecGrpParmName: 'RdsVpcSecurityGroupId',
    ResourceGroupsTaggingApiParms: {
      ResourceTypeFilters: [
        'cloudformation:stack'
      ],
      TagFilters: [
        {
          Key: 'Service',
          Values: [ 'research-administration' ]
        },
        {
          Key: 'Function',
          Values: [ 'kuali' ]
        },
        {
          Key: 'Category',
          Values: [ 'application', 'app' ]
        },
        {
          Key: 'Baseline',
          Values: [ baseline ]
        }
      ]
    },
    CloudFormationParms: {
      StackStatusFilter: [
        'CREATE_COMPLETE',
        'ROLLBACK_COMPLETE',
        'UPDATE_COMPLETE',
        'UPDATE_ROLLBACK_COMPLETE',
        'IMPORT_COMPLETE',
        'IMPORT_ROLLBACK_COMPLETE'
      ]
    }
  }

  this.getStacks = async () => {
    return await (new CloudFormationInventory()).getStacks(parms);
  }
}