## Kuali Web Application Firewall

*Intended for inclusion as a nested stack in parent stacks - not as its own stack*

The cloudformation template here will create a [Web Application Firewall (WAF)](https://aws.amazon.com/waf/)

> *AWS WAF is a web application firewall that helps protect your web applications or APIs against common web exploits that may affect availability, compromise security, or consume excessive resources. AWS WAF gives you control over how traffic reaches your applications by enabling you to create security rules that block common attack patterns, such as SQL injection or cross-site scripting, and rules that filter out specific traffic patterns you define. You can get started quickly using Managed Rules for AWS WAF, a pre-configured set of rules managed by AWS or AWS Marketplace Sellers. The Managed Rules for WAF address issues like the OWASP Top 10 security risks.*

The firewall is based on the default configuration of the [aws-waf-security-automations.template](https://s3.amazonaws.com/solutions-reference/aws-waf-security-automations/v2.3.3/aws-waf-security-automations.template) which deploys an AWS WAF web ACL with eight preconfigured rules.

### Why do we need a WAF?

Without a WAF, any application sitting behind a publicly available load balancer whose ports (typically 80 and 443) with global cidr IP access (`0.0.0.0/0`),  is not looking at http requests as potentially containing attacks.
NAT provides some security for unsolicited traffic, but the ALBs are sitting in public subnets and servicing public requests which need to prove they are not dangerous by obeying the rules configured into the WAF.

Alternatively, the only way to provide enough protection without a WAF is to restrict the security groups associated to the ALB to allow only traffic from cidr IP ranges of BU VPNs. This however would take the application out of the public category as one would need to be logged on to the BU network in order to access the app (no "coffee shop" access).

### Upload the template to S3:

Any updates to the template should be followed by an upload to s3 to keep things in sync:

```
cd kuali_waf
sh upload.sh profile=[your profile]
```

