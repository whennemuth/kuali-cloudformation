## Kuali Research Cloud Deployments on AWS

This repository provides several folders, each corresponding to the creation of a cloudformation stack and containing the associated templates and helper scripts for their use.

> **BU Targeted**: This branch is specific to deployment to the buaws-istcloud-infrastructure account for applications. It is NOT a "vanilla" cloud deployment for Kuali Research. That is, it deploys into pre-existing network infrastructure comprising resources like VPN, Transit Gateway,NAT, Routing, etc.
>
> A **"vanilla"** version is available in a separate branch and - apart from s3 buckets, databases, and the proper IAM presence for you to cloud-form - the account in which you are running these stacks could be brand new and bare of anything else. All resources from the VPN down would be created from scratch.

Once created, a stack will have created a deployment of the kuali-research application and accompanying modules within the specified aws account.

These stacks are as follows, in order of increasing scope:

- [Deployent on a single EC2 instance](kuali_ec2/README.md)
- [Deployment on two EC2 instances behind a load balancer](kuali_ec2_alb/README.md)
- [Deployment across an Elastic Container Services (ECS) cluster](kuali_ecs/README.md)

The following are stacks that have accumulated over time that serve as cloudbased services to kuali research deployments that were not necessarily created through cloudformation. 
However, for the stacks referenced above, these "peripherals" may be incorporated as nested stacks.

- [Kuali Peripheral Services](kuali_peripherals/README.md)

  