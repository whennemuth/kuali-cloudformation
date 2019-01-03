## AWS ECS Cloud formation stack for Kuali-Research

### <u>Overview</u>

These json files comprise the templates for building an AWS cloud formation stack where all Kuali research modules are hosted through elastic container services (ECS).
For a starting point, all that is needed is:

1. An AWS account
2. An administrative IAM user with sufficient privileges to access these templates through the S3 service and create the resources called for in each one.

### <u>Steps</u>

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
Upgrades/releases to kuali modules as well as scheduled system maintenance or updates to the EC2 instances in the ECS cluster would be performed through stack updates.

### <u>Stack Breakdown</u>

1. [main.template](main.template)
   All other templates are nested templates. This is the main template that invokes them all and comprises the whole stack set from Network infrastructure all the way to ECS task definitions.

   RESOURCES :

   - [AWS::Cloudformation:Stack](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html)

   NOTES:

   - NONE YET

2. [vpc.template](vpc.template)
   Creates a new virtual private cloud for our services with subnets, gateways, and route tables.

   RESOURCES :

   - [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
   - [AWS::EC2::InternetGateway](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-internetgateway.html)
   - [AWS::EC2::VPCGatewayAttachment](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc-gateway-attachment.html)
   - [AWS::EC2::EIP](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-eip.html)
   - [AWS::EC2::NatGateway](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-natgateway.html)
   - [AWS::EC2::RouteTable](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-route-table.html)
   - [AWS::EC2::Route](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-route.html)
   - [AWS::EC2::SubnetRouteTableAssociation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet-route-table-assoc.html)

   NOTES:

   - NONE

3. [subnet.template](subnet.template)
   This template will create 2 private subnets whose CIDR blocks depends on the specified landscape and have 128 IPs each. 

   RESOURCES :

   - [AWS::EC2::Subnet](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html)

   NOTES:

   - The goal is to have ready 2 subnets that the ECS cluster that corresponds to the landscape can span. As of now, there are 5 environments and the EC2 instances of the associated ECS cluster run in two availability zones, at least one of which overlaps with another landscape. This means 5 total availability zones across the landscapes. Currently us-east-1 will support this as it has zones A-F

4. [security-group.template](security-group.template)
   Establishes the security groups required throughout the VPC

   RESOURCES :

   - [AWS::EC2::SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-security-group.html)

   NOTES:

   - NONE

5. [alb.template](alb.template)
   This template deploys an application load balancer that exposes the ECS services.

   RESOURCES :

   - [AWS::ElasticLoadBalancingV2::LoadBalancer](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-loadbalancer.html)
   - [AWS::ElasticLoadBalancingV2::Listener](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-listener.html)
   - [AWS::ElasticLoadBalancingV2::TargetGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-targetgroup.html)

   NOTES:

   - We define a default target group in this template, as this is a mandatory parameter when creating an Application Load Balancer Listener. This is not used, instead a target group is created per-service in each service template. In order for the load balancer created in this template to load balance for the services, its LoadBalancerListener  is output from this template and fed in as a parameter to each service template, where it is set as a property of the ListenerRule of the TargetGroup of the service.

6. [cluster.template](cluster.template)
   This template defines EC2 instance creation for the ECS container instances that form the ECS cluster.     RESOURCES :

   - [AWS::EC2::Instance](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-instance.html)
   - [AWS::EC2::SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-security-group.html)
   - [AWS::IAM::Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-role.html)
   - [AWS::IAM::InstanceProfile](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-instanceprofile.html)

   NOTES:

   - [What does and does not get changed when an EC2 instance undergoes a stack update](notes/ecs-cluster.md)

7. [lifecycle-hook.template](lifecycle-hook.template)
   A [lifecycle hook](https://docs.aws.amazon.com/autoscaling/ec2/APIReference/API_LifecycleHook.html) tells Auto Scaling that you want to perform an action whenever it launches instances or whenever it terminates instances. For this ECS environment, we want to use the lifecycle hook to accomplish [Container Instance Draining](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-instance-draining.html).
   RESOURCES :

   - [AWS::AutoScaling::LifecycleHook](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-as-lifecyclehook.html)
   - [AWS::SNS::Topic](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-sns-topic.html)
   - [AWS::IAM::Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-role.html)
   - [AWS::Lambda::Function](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-function.html)
   - [AWS::Lambda::Permission](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-permission.html)

   NOTES:

   - [Container instance draining is not to be confused with connection draining](notes/lifecycle-hook.md)

8. [service-core.template](service-core.template)
   This service contains one task definition that runs the kuali cor-main application. Basically a docker image is defined along with policies for auto-scaling it as docker containers across the cluster and a tie-in with the application load balancer created earlier.

   RESOURCES :

   - [AWS::ECS::Service](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-service.html)
   - [AWS::ECS::TaskDefinition](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskdefinition.html)
   - [AWS::Logs::LogGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-logs-loggroup.html)
   - [AWS::ElasticLoadBalancingV2::TargetGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-targetgroup.html)
   - [AWS::ElasticLoadBalancingV2::ListenerRule](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-listenerrule.html)
   - [AWS::IAM::Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-role.html)
   - [AWS::ApplicationAutoScaling::ScalableTarget](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-applicationautoscaling-scalabletarget.html)
   - [AWS::ApplicationAutoScaling::ScalingPolicy](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-applicationautoscaling-scalingpolicy.html)
   - [AWS::CloudWatch::Alarm](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-cw-alarm.html)

   NOTES:

   - NONE

