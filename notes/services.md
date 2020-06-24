### Notes on Services

The following are a few links and noteworthy points encountered while developing the service portion of the ECS cluster stack creation:

- [`AWS::ECS::Service`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-service.html)
  [Service Load Balancing](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-load-balancing.html): Currently, Amazon ECS services can only specify a single load balancer or target group. If your service requires access to multiple load balanced ports (for example, port 80 and port 443 for an HTTP/HTTPS service), you must use a Classic Load Balancer with multiple listeners. To use an Application Load Balancer, separate the single HTTP/HTTPS service into two services, where each handles requests for different ports. Then, each service could use a different target group behind a single Application Load Balancer.

- [`AWS::ElasticLoadBalancingV2::ListenerRule`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-listenerrule.html)
  Recently released: [HTTPS redirection](https://forums.aws.amazon.com/thread.jspa?threadID=286855&start=25&tstart=0)

- [`AWS::ECS::TaskDefinition`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskdefinition.html)
  The docker containers launched for the core TaskDefinition use HostPorts that are dynamically mapped. This allows for more granular auto-scaling where more than one instance of the same container can be run on the same ContainerHost (ec2 instance).
  To do this, the ContainerDefinitions must:

  - Use the bridge NetworkMode setting
  - Use PortMappings where the HostPort is left blank (or set to 0)

  Links:

  - [API: Port Mapping](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)
  - [API: Register Task Definition](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_RegisterTaskDefinition.html)
  - [Task Definition Parms: Network Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#network_mode)

- [`AWS::ApplicationAutoScaling::ScalingPolicy`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-applicationautoscaling-scalingpolicy.html)
  We are using step scaling policy and not target tracking scaling policy. While target tracking is a simple, aws creates and manages the cloudformation alarms, which prevents the opportunity for you to create your own custom metric based alarms and have more control in general.

- [`AWS::CloudWatch::Alarm`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-cw-alarm.html)
  If you're looking for documentation on how cloudwatch metrics are aggregated across the cluster/service in order to properly trigger scaleout/scalein alarms, you can find it here:

  - [Cloudwatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch-metrics.html)
  - [Alarms that send email](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)