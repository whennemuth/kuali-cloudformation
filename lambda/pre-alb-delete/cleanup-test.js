var cleanup = require('./cleanup.js');

process.env.ALB_BUCKET_NAME = 'kuali-ecs-alb';
process.env.WAF_BUCKET_NAME = 'kuali-ecs-alb-waf';
process.env.ATHENA_BUCKET_NAME = 'kuali-ecs-alb-athena';
process.env.LOAD_BALANCER_ARN = 'arn:aws:elasticloadbalancing:us-east-1:770203350335:loadbalancer/app/kuali-ec2-alb-ci-alb/70f8b6a31453bcf5';
process.env.WAF_ARN = 'arn:aws:wafv2:us-east-1:770203350335:regional/webacl/kuali-ec2-alb-ci-WAF-1UW7WPNVJKTHT-WAF-1A6FES8084UM0/1d820753-d367-4f29-84a2-354ffdea145f';


var myEvent = {
  ResourceProperties: {
    resource: 'waf',
    // target: 'bucket'
  },
  RequestType: 'Delete'
}

cleanup.handler(myEvent, null);
