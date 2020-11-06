## Kuali Web Application Firewall

*Intended for inclusion as a nested stack in parent stacks - not as its own stack*

The cloudformation template here will create a [Web Application Firewall (WAF)](https://aws.amazon.com/waf/)

> *AWS WAF is a web application firewall that helps protect your web applications or APIs against common web exploits that may affect availability, compromise security, or consume excessive resources. AWS WAF gives you control over how traffic reaches your applications by enabling you to create security rules that block common attack patterns, such as SQL injection or cross-site scripting, and rules that filter out specific traffic patterns you define. You can get started quickly using Managed Rules for AWS WAF, a pre-configured set of rules managed by AWS or AWS Marketplace Sellers. The Managed Rules for WAF address issues like the OWASP Top 10 security risks.*

The firewall is based on the default configuration of the [aws-waf-security-automations.template](https://s3.amazonaws.com/solutions-reference/aws-waf-security-automations/v2.3.3/aws-waf-security-automations.template) which deploys an AWS WAF web ACL with eight preconfigured rules. In addition to this, 

1. An [Amazon Kinesis Data Firehose](https://docs.aws.amazon.com/firehose/latest/dev/what-is-this-service.html) is created to capture and stream WAF data into a data lake built on... 
2. [Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/dev/Welcome.html). Three separate S3 buckets in total are created.
3. An [AWS Glue](https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html) database is also created and used to catalog the S3 bucket content for analysis with tools like [Athena](https://docs.aws.amazon.com/athena/latest/ug/what-is.html) or [Redshift](https://docs.aws.amazon.com/redshift/latest/mgmt/welcome.html).

### Why do we need a WAF?

Without a WAF, any application sitting behind a publicly available load balancer whose ports (typically 80 and 443) with global cidr IP access (`0.0.0.0/0`),  is not looking at http requests as potentially containing attacks.
NAT provides some security for unsolicited traffic, but the ALBs are sitting in public subnets and servicing public requests which need to prove they are not dangerous by obeying the rules configured into the WAF.

Alternatively, the only way to provide enough protection without a WAF is to restrict the security groups associated to the ALB to allow only traffic from cidr IP ranges of BU VPNs. This however would take the application out of the public category as one would need to be logged on to the BU network in order to access the app (no "coffee shop" access).

### Architecture:

*Note: Our implementation does not include [cloudfront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html) in the web app resources as depicted below, just the ALB.* 

![architecture](./architecture.png)

### Kuali specific adjustments:

- **Lambda function to turn on WAF logging**:
  Content pending...
- **Lambda function to cleanup S3 after stack deletion:**
  Content pending...
- **Lambda function to adjust WAF WebAcl rules**:
  Content pending...

### Upload the template to S3:

Any updates to the template should be followed by an upload to s3 to keep things in sync:

```
cd kuali_waf
sh upload.sh profile=[your profile]
```

### Additional links/documentation:

- [AWS WAF security automations source code](https://github.com/awslabs/aws-waf-security-automations)
  This is a useful for answering certain specific questions as to how the WAF stack works.
- [aws-waf-and-shield-advanced-developer-guide](https://github.com/awsdocs/aws-waf-and-shield-advanced-developer-guide)
  Contains tons of in depth documentation on WAF specifics.
- [How can I detect false positives caused by AWS Managed Rules and add them to a safe list?](https://aws.amazon.com/premiumsupport/knowledge-center/waf-detect-false-positives-from-amrs/)