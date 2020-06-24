## Kuali Peripherals

The following are stacks that have accumulated over time that serve as cloudbased services to forerunning kuali research deployments that were not necessarily created through cloudformation. 
Predating the main deployment stacks in this repository, they stand up adjunct cloud services for the prior kuali research deployments.

Going forward, the primary deployment stacks in this repository may incorporate these "peripherals" as nested stacks.

- [**ElasticSearch Service**](es_for_kuali.md)
  Powers the omni-search feature of the Kuali dashboard. The template is [here](es_for_kuali.md)
  
- **Additional Roles/Policies**
  Over time EC2 instances that host kuali research have required access to other aws resources and the corresponding roles and polices that will grant that access. 
  Also, the EC2 instance that runs Jenkins and operates as our build/CI server requires special privileges that grew in number.
  Access is divided into policy actions that are grouped into roles. One or more of these roles are bundled into an EC2 profile and applied to the EC2 instance. The profiles created here allow an EC2 instance to:
  
  - Execute operational actions or direct commands against other EC2 instances via the AWS System Manager (SSM)
  - Have access to read and write to certain S3 buckets
  - Send emails through the Simple Email Service (SES)
  - Send metrics and other logging data to cloudwatch
  - Have pull access (and push in the case of Jenkins) to the Elastic Container Registry (ECS)
  
  The template is [here](iam_for_kuali.yaml)
  
- **S3 buckets for the Kuali PDF service**
  The Pdf service for kuali research needs a bucket to stage newly created pdf files. This stack includes one bucket for a specified landscape, or one for every landscape. Objects sent to the bucket will last for 30 days with the standard storage class to then be converted to the One Zone-Infrequent Access class. Deletion occurs after a year.
  The template is [here](s3_for_research_pdf.yaml)

