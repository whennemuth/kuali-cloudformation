## Kuali RDS

Use this template to create a single RDS database instance or cluster of RDS database instances for kuali-research.

### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS commandline iterface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)
- **AWS Session Manager Plugin**
  You will need this to connect to the RDS instance via a jump server ec2 instance once they are created.
  This plugin allows the AWS cli to launch Session Manager sessions with your local SSH client. The Version should be should be at least 1.1.26.0.
  Install instructions: [Install the Session Manager Plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

### Steps:

Included is a bash helper script (main.sh) that serves to simplify many of the command line steps that would otherwise include a fair amount of manual entry. 

1. **Clone this repository**:

   ```
   git clone https://github.com/bu-ist/kuali-infrastructure.git
   cd kuali-infrastructure/kuali_rds
   ```

2. **Create the stack:**
   Use the helper script (main.sh) to create the cloudformation stack:
   NOTES ON PARAMETERS:

   - It is recommended to accept the defaults.
   - All of the subnet-oriented parameters will be dynamically looked up using the cli, though they can be provided as explicit parameters. 
     These subnets are tagged to identify which is which.
   - The stack_name parameter and the landscape parameter will be combined to form the actual stack name.
     This allows for one stack per environment in the same account.
   - The multi_az parameter defaults to true, so you must explicitly indicate false if you only want a single rds instance.
     **Important:** *Multi-AZ deployments are not a read scaling solution, you cannot use a standby replica to serve read traffic. The standby is only there for failover.*
   
   You will always be presented with the final cli stack creation command so that you can look at all the parameters it contains and will have the option to abort. Saves fear of guesswork. Those parameters you don't see can be located in the yaml template for the default value.
   
   ```
   # Example 1) All defaults, among which is "sb" for the environment, and "true" for multi-az
   sh main.sh create-stack 
   
   # Example 2) Recommended for ci and qa landscape, using single rds instance in one availability zone (it's CI, so only one needed)
   sh main.sh create-stack landscape=ci multi_az=false
   
   # Example 3) Recommended for prod (and possibly stg). Multi_az and larger than default instance size.
   sh main.sh create-stack landscape=prod db_instance_class=db.m5.xlarge
   
   # Example 3) You would probably never need to override ALL parameters, but if you did, it would look like this:
   sh main.sh create-stack profile=myprofile landscape=ci stack_name=my-kuali-rds global_tag=my-kuali-rds no_rollback=true bucket_path=s3://kuali-conf/cloudformation/kuali_rds db_instance_class=db.r4.xlarge engine=oracle-ee engine_version=12.1.0.2.v20  db_name=Kuali port=1521 license_model=license-included multi_az=false allocated_storage=400 db_snapshot_arn=[some arn] auto_version_minor_upgrade=false backup_retention_period=10 characterset_name=US7ASCII iops=4000 campus_subnet1=subnet-06edbf07b7e07d73c campus_subnet1_cidr=10.58.34.0/24 campus_subnet2=subnet-0032f03a478ee868b campus_subnet2_cidr=10.58.35.0/24 private_subnet1=subnet-0d4acd358fba71d20 private_subnet1_cidr=10.58.33.0/25 private_subnet2=subnet-08afdf870ee85d511 private_subnet2_cidr=10.58.33.128/25 public_subnet1=subnet-07afd7c2e54376dd0 public_subnet1_cidr=10.58.32.0/25 public_subnet2=subnet-03034a40da92d6d08 public_subnet2_cidr=10.58.32.128/25 jumpbox_instance_type=t3.small
   
   ```
   
   Once you initiate stack creation, you can go to the aws management console and watch the stack creation events as they come in:
   [AWS Management Console - Cloudformation](https://console.aws.amazon.com/cloudformation/home?region=us-east-1)
3. **Monitor stack progress:**
   Go to the stack in the [AWS Console](https://console.aws.amazon.com/cloudformation/home?region=us-east-1). Click on the new stack in the list and go to the "Events" tab.
   Watch for failures (these will show up in red).

4. **Obtain the master user password:**

   ```
   aws --profile [your.profile] secretsmanager get-secret-value \
       --secret-id kuali/[landscape]/oracle-rds-password \
    --output text \
       --query '{SecretString:SecretString}' \
       | jq '.MasterUserPassword' \
       | sed 's/"//g'
       
   NOTE: If you ever have to delete the secret, this is how:
   aws secretsmanager delete-secret --secret-id kuali/sb/oracle-rds-password --force-delete-without-recovery
   ```
   
5. **Connect to the database instance:**

   ------

   ​            BACKGROUND:

   ------

   From outside the its vpc, the kuali rds instance is connected to via an ec2 instance serving as a "jump box".
   Overall, database access for kuali is secure and fairly well isolated from everything outside of its [vpc](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).
   This is because the following are true:

   - The RDS instance(s) have endpoints that are not publicly accessible.
   - The jump server has only a private ip address.
   - The private subnet has only a route to a NAT gateway, so no ingress can be initiated to either the database or the jumpbox instances from outside of the vpc.
   - The jump server resides in the same private subnet as the database instance/cluster.
      This distinguishes it from a bastion server, better to refer to it as a "jump box".
      This also brings the same level of isolation to the jump server as for the database instances themselves *(but there's still a way in - see below)*.
   - The security group for the jump server allows ingress over only one port (1521) and only for traffic originating from either of the two private database subnets.
   - The security group for the database instances allows ingress over only one port (1521) and only for traffic originating from either of the two private subnets or either of the two campus subnets (where the application servers reside).

   With the jump box locked down in this way, and no SSH ports open to it, it's worth considering how to get to it.
   It has a role that allows access through ssm. For instance, you could shell into it and poke around like this:

   ```
   aws ssm start-session --target [instance-id of jump server]
   ```

   In the case of establishing an SSH connection to the RDS instance, the jump server is necessary to proxy the start-session command.
   This is because you cannot execute such a command directly against the RDS instance itself due to the `--target` parameter requiring an ec2 instance id, which an RDS instance does not have.
   This makes for a somewhat more involved set of commands, but for which there is a helper script.

   ------

   ​            HELPER SCRIPT:

   ------

   To connect to the master RDS instance, the helper script follows the approach from these references:

   - [Secure RDS Access through SSH over AWS SSM](https://codelabs.transcend.io/codelabs/aws-ssh-ssm-rds/index.html#6)
   - [Enable SSH connections through Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html)

   ```
   # Example:
   sh main.sh tunnel \
     profile infnprd \
     rds_endpoint=kuali-oracle-sb.clb9d4mkglfd.us-east-1.rds.amazonaws.com \
     jumpbox_instance_id=i-02b4dd8149bd0f9fa
   ```

6. 

   

   

   