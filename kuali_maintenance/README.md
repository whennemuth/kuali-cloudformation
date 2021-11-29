## Kuali Maintence

This cloudformation stack creates a small EC2 instance that can replace the kuali service with an nginx server running in a docker container that issues a single web page for all links to the domain displaying a generic message like "Down for maintenance". Currently the default message indicates that the research administration service has moved to a new location and provides the link (T.

### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)
- **SSL Certificate & Key**
  When the ec2 instance bootstraps itself, it will attempt to acquire the ssl certificate and private key for the domain of kuali research for the specified environment from an s3 bucket. The nginx server needs these to properly service any secure (https) web requests. For the legacy Kuali aws account, these have been placed in the following locations:
  - [**ci:** https://kuali-research-ec2-setup.s3.amazonaws.com/ci/certs](https://s3.console.aws.amazon.com/s3/buckets/kuali-research-ec2-setup?region=us-east-1&prefix=ci/certs/&showversions=false)
  - [**staging:** https://kuali-research-ec2-setup.s3.amazonaws.com/stg/certs](https://s3.console.aws.amazon.com/s3/buckets/kuali-research-ec2-setup?region=us-east-1&prefix=stg/certs/&showversions=false)
  - [**production:** https://kuali-research-ec2-setup.s3.amazonaws.com/prod/certs](https://s3.console.aws.amazon.com/s3/buckets/kuali-research-ec2-setup?region=us-east-1&prefix=prod/certs/&showversions=false)

### Steps:

1. **Create the cloudformation stack:**

   ```
   cd kuali_maintenance
   sh main.sh create-stack landscape=[ci, stg, or prod] profile=[your iam profile]
   ```

2. **Update the load balancer:**
   The prior step will have created a micro ec2 instance in the account. At this point this instance is not publicly reachable and cannot service any web requests. In order for the ec2 instance to swap places with the currently running kuali application, it needs to displace the associated ec2 instances from the load balancer for the service:

   ```
   cd kuali-maintenance
   sh main.sh elb-swapout landscape=[ci, stg, or prod] profile=[your iam profile]
   ```

   This automatically performs what would otherwise break down into the following manual steps:

   1. Locate the load balancer for the applicable landscape. For the legacy kuali aws account, these are located [here](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#LoadBalancers:sort=loadBalancerName)
   2. On the "Instances" tab, remove the 2 ec2 instances currently associated with the load balancer and replace them with the one named "kuali-maintenance-*[landscape]*".

3. **Confirm in browser:**
   Navigate to any kuali research link for the applicable landscape and confirm the maintenance page shows up.

