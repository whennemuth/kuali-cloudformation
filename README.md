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
Upgrades/releases to kuali-research as well as scheduled system maintenance or updates to the ec2 instances in the ECS cluster would be performed through stack updates.

### <u>Stack Breakdown</u>

1. [main.template](main.template)
2. [vpc.template](vpc.template)
3. [subnet.template](subnet.template)
4. [security-group.template](security-group.template)
5. [alb.template](alb.template)
   NOTE: We define a default target group in this template, as this is a mandatory parameter when creating an Application Load Balancer Listener. This is not used, instead a target group is created per-service in each service template. In order for the load balancer created in this template to load balance for the services, its LoadBalancerListener  is output from this template and fed in as a parameter to each service template, where it is set as a property of the ListenerRule of the TargetGroup of the service.
6. [cluster.template](cluster.template)
7. [lifecycle-hook.template](lifecycle-hook.template)
   
   A [lifecycle hook](https://docs.aws.amazon.com/autoscaling/ec2/APIReference/API_LifecycleHook.html) tells Auto Scaling that you want to perform an action whenever it launches instances or whenever it terminates instances. For this ECS environment, we want to use the lifecycle hook to accomplish [Container Instance Draining](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-instance-draining.html).
   
   NOTE: Container instance draining is not to be confused with connection draining.
   1. **[Connection Draining](https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/config-conn-drain.html):**
      If you want to ensure that in-flight requests are completed before the ec2 instance servicing the request is de-registered for health check failure or a scaling event, you enable connection draining. This involves either 
      **a)** <u>Classic ELB</u>: [AWS::ElasticLoadBalancing::LoadBalancer.Properties.ConnectionDrainingPolicy.Enabled:true,Timeout:[seconds]](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-elb.html#aws-resource-elasticloadbalancing-loadbalancer-example3.json)
            or...
      **b)** <u>V2 ELB</u>: [AWS::ElasticLoadBalancingV2::TargetGroup.Properties.TargetGroupAttributes.Key:deregistration_delay.timeout_seconds,Value:[seconds]](https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_TargetGroupAttribute.html)
      We use the V2 ELB, but in either case, the timeout setting specifies how long to wait for in-flight requests to complete and the de-registration to proceed.
   2. **[Container Instance Draining](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-instance-draining.html):**
      Connection draining essentially prevents the client from experiencing the server being cut off in mid-reply to a request that was made to one of its tasks. But container instance draining involves a special transitional state applied to a container instance having to do with its lifecycle.
      You put the container instance into a DRAINING state, which prevents new tasks from being launched and signals ECS to put replacement tasks on other instances in the cluster.
      You would then watch while the container instance is "drained" of its tasks as ECS attempts to maintain capacity, as defined in the minimum/maximum HealthyPercent configuration of the service, by redistributing it on the non-draining instances in the cluster.
      Terminating the instance without draining it could cause a disruption to this process - ECS would be unable ensure the proper capacity of the service (at least for a while).
               *<u>Lamdbda function</u>*: In this template we [automate](https://aws.amazon.com/blogs/compute/how-to-automate-container-instance-draining-in-amazon-ecs/) container instance draining by creating an event that is triggered when a container instance goes into a TERMINATING transition whereby the event calls a lambda function that holds the container instance in a DRAINING state until all tasks have been stopped. It then lets ECS complete the TERMINATING transition. This lambda function is essentially a for loop and a sleep statement that loops through each task in the service on the instance at an interval and only removes the DRAINING state when all tasks are found to have been stopped (loop exits). You can also include in the lambda function whatever other custom functionality you need.
8. [service-core.template](service-core.template)

