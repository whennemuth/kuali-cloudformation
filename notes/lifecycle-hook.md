## NOTES: Lifecycle Hook

1. #### Container instance draining is not to be confused with connection draining.

   > **TERMINOLOGY**
   >
   > [Container Instance](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_instances.html):
   >
   > > *An Amazon ECS container instance is an Amazon EC2 instance that is running the Amazon ECS container agent and has been registered into a cluster.* 
   >
   > [Task Definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html):
   >
   > > *After an Amazon ECS cluster is up and running, you can define task definitions and services that specify which Docker container images to run across your clusters. Container images are stored in and pulled from docker container registries.* 



   - [Connection Draining](https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/config-conn-drain.html):
      If you want to ensure that in-flight requests are completed before the EC2 instance servicing the request is de-registered for health check failure or a scaling event, you enable connection draining. This one of the following:

      | Load balancer type | Connection Draining Configuration                            |
      | :----------------- | :----------------------------------------------------------- |
      | Classic ELB        | [AWS::ElasticLoadBalancing::LoadBalancer.Properties.ConnectionDrainingPolicy.Enabled:true,Timeout:[seconds]](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-elb.html#aws-resource-elasticloadbalancing-loadbalancer-example3.json) |
      | V2 ELB             | [AWS::ElasticLoadBalancingV2::TargetGroup.Properties.TargetGroupAttributes.Key:deregistration_delay.timeout_seconds,Value:[seconds]](https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_TargetGroupAttribute.html) |

      We use the V2 ELB, but in either case, the timeout setting specifies how long to wait for in-flight requests to complete and the de-registration to proceed.

   - [Container Instance Draining](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-instance-draining.html):
      Connection draining essentially prevents the client from experiencing the server being cut off in mid-reply to a request that was made to one of its tasks. But container instance draining involves a special transitional state applied to a container instance having to do with its lifecycle.
      You put the container instance into a DRAINING state, which prevents new tasks from being launched and signals ECS to put replacement tasks on other instances in the cluster.
      You would then watch while the container instance is "drained" of its tasks as ECS attempts to maintain capacity, as defined in the minimum/maximum HealthyPercent configuration of the service, by redistributing it on the non-draining instances in the cluster.
      Terminating the instance without draining it could cause a disruption to this process - ECS would be unable ensure the proper capacity of the service (at least for a while).
      ​         *<u>Lamdbda function</u>*: In this template we [automate](https://aws.amazon.com/blogs/compute/how-to-automate-container-instance-draining-in-amazon-ecs/) container instance draining by creating an event that is triggered when a container instance goes into a TERMINATING transition whereby the event calls a lambda function that holds the container instance in a DRAINING state until all tasks have been stopped. It then lets ECS complete the TERMINATING transition. This lambda function is essentially a for loop and a sleep statement that loops through each task in the service on the instance at an interval and only removes the DRAINING state when all tasks are found to have been stopped (loop exits). You can also include in the lambda function whatever other custom functionality you need.

2. 