## AWS ECS Cloud formation stack for Kuali-Research

### Overview

These json files comprise the templates for building an AWS cloud formation stack where all Kuali research modules are hosted through elastic container services (ECS).
For a starting point, all that is needed is:

1. An AWS account
2. An administrative IAM user with sufficient privileges to access these templates through the S3 service and create the resources called for in each one.

### Steps

**Stack creation**
Follow AWS stack creation directions in their standard documentation [here](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-create-stack.html)
Once you click "Create stack" or "Create new stack"

- [Selecting a stack template](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-using-console-create-stack-template.html): 
  Go with the option titled: "Specify an Amazon S3 template URL" and specify the S3 url for main.template. In our existing AWS account the location of main.template is:

  ```
  https://s3.amazonaws.com/kuali-research-ec2-setup/ecs/cloudformation/main.template
  ```

- [Specifying Stack Name and Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-using-console-create-stack-template.html)
  **Stack name**: this is used by the cloud formation templates to prefix the names of the resources they create for easy identification in the management console among other resources that are not part of the stack. Therefore, a short name is recommended.
  **Parameter defaults**: these are the best fit for what we are running as kuali-research, and while you can play around with different settings, the defaults are recommended.
  ***NOTE:*** *By default, the "Rollback on failure" choice in the advanced section is enabled. This means that if any one of the templates should fail, all resources created by prior templates are removed, bringing you back to where you started. You can disable this if you want see everything created up to a point.*

- [Setting AWS CloudFormation Stack Options](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-using-console-create-stack-template.html)
  You can skip by all of these options and click "Next" at the bottom

- [Reviewing Your Stack and Estimating Stack Cost on the AWS CloudFormation Console](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-using-console-create-stack-template.html)
  Check the acknowledgement box and click "Create"

**Stack updates**
You can either [Update the stack directly](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-direct.html), or [Update the stack using a changeset](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-direct.html), but if you want AWS to present a prediction of what affects the update will have (particularly deletions) before the update is implemented, then use the changeset.
In any event, the updates would be written into the template file(s) and re-uploaded to the S3 bucket before starting. The stack update wizard will present you with the option of specifying the S3 url to update the stack or nested stack(s). This would not be necessary if simply updating to implement different parameters.
Upgrades/releases to kuali-research as well as scheduled system maintenance or updates to the ec2 instances in the ECS cluster would be performed through stack updates. See the  

### Stack Breakdown

1. [main.template](main.template)
2. [vpc.template](vpc.template)
3. [subnet.template](subnet.template)
4. [security-group.template](security-group.template)
5. [alb.template](alb.template)
6. [cluster.template](cluster.template)
7. [service-core.template](service-core.template)

