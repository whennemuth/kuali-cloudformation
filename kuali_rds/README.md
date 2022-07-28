## Kuali Oracle RDS Stack Creation

Create the following:

- A single RDS database instance or cluster of RDS database instances for kuali-research.
- A small ec2 instance to serve as a jump server to the RDS instance(s)

No Kuali schema creation/population is done here. To take that next step, follow [these migration instructions](migration/README.md)*

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
  
   - **Creation:**
      Use the helper script (main.sh) to create the cloudformation stack:
      NOTES ON PARAMETERS:
   
      1. It is recommended to accept the defaults.
      2. All of the subnet-oriented parameters will be dynamically looked up using the cli, though they can be provided as explicit parameters. 
        These subnets are tagged to identify which is which.
      3. The stack_name parameter and the landscape parameter will be combined to form the actual stack name.
        This allows for one stack per environment in the same account.
      4. The `multi_az` parameter defaults to false, so you must explicitly indicate true if want a standby replica and not just a single rds instance.
        **Important:** *Multi-AZ deployments are not a read scaling solution, you cannot use a standby replica to serve read traffic. The standby is only there for failover.*
      5. **DNS:** If you are recreating the stack and want to avoid the hassle of having end users update the database host with the new RDS endpoint value, include a `"USING_ROUTE53=true"` parameter. The database will be reachable at `[landscape].db.kualitest.research.bu.edu` for non-prod stacks and `prod.db.kuali.research.bu.edu` for the prod stack. End users can retain that hostname in their connection string and retain access even though the RDS database is new and has a different endpoint value.
   
      You will always be presented with the final cli stack creation command so that you can look at all the parameters it contains and will have the option to abort. Saves fear of guesswork. Those parameters you don't see can be located in the yaml template for the default value.
   
      ```
      # Example 1) Create a blank database (schema creation comes later as in database migration).
      sh main.sh create-stack profile=default landscape=ci
      
      # Example 2) Recommended for prod (and possibly stg). Is Multi_az, and larger than default instance size, and DNS.
      sh main.sh create-stack \
        profile=default \
        landscape=prod \
        using_route53=true \
        db_instance_class=db.m5.xlarge multi_az=true \
        rds_snapshot_arn=arn:aws:rds:us-east-1:770203350335:snapshot:rds:some-snapshot-name
      
      # Example 3) Create a new rds instance based on a snapshot of another rds instance.
      sh main.sh create-stack \
        profile=default \
        landscape=mylandscape \
        rds_snapshot_arn=arn:aws:rds:us-east-1:770203350335:snapshot:rds:some-snapshot-name
      # or create a new snapshot from the rds instance that services the specified landscape...
      sh main.sh create-stack \
        profile=default \
        landscape=mylandscape \
        rds_landscape_to_clone=stg
      
      # Example 4) You would probably never need to override ALL parameters, but if you did, it would look like this:
      sh main.sh create-stack profile=myprofile landscape=ci stack_name=my-kuali-rds global_tag=my-kuali-rds no_rollback=true template_bucket_path=s3://kuali-conf/cloudformation/kuali_rds db_instance_class=db.r4.xlarge engine=oracle-ee engine_version=12.1.0.2.v20  db_name=Kuali port=1521 license_model=license-included multi_az=false allocated_storage=400 rds_snapshot_arn=[some arn] auto_version_minor_upgrade=false backup_retention_period=10 characterset_name=US7ASCII iops=4000 campus_subnet1=subnet-06edbf07b7e07d73c campus_subnet1_cidr=10.58.34.0/24 campus_subnet2=subnet-0032f03a478ee868b campus_subnet2_cidr=10.58.35.0/24 private_subnet1=subnet-0d4acd358fba71d20 private_subnet1_cidr=10.58.33.0/25 private_subnet2=subnet-08afdf870ee85d511 private_subnet2_cidr=10.58.33.128/25 public_subnet1=subnet-07afd7c2e54376dd0 public_subnet1_cidr=10.58.32.0/25 public_subnet2=subnet-03034a40da92d6d08 public_subnet2_cidr=10.58.32.128/25 jumpbox_instance_type=t3.small version_12_compatibility=true
      
      ```
   
      Once you initiate stack creation, you can go to the aws management console and watch the stack creation events as they come in:
      [AWS Management Console - Cloudformation](https://console.aws.amazon.com/cloudformation/home?region=us-east-1)
   
   - **Re-creation/replacement:**
      This is a scenario in which an existing rds database is to be deleted and replaced with a new one.
      Use the helper script (main.sh) to create the cloudformation stack.
      Examples:
   
      ```
      # Example 1) Replace an rds database in one command
      sh main.sh recreate-stack \
        profile=default \
        landscape=mylandscape \
        using_route53=true \
        rds_snapshot_arn=arn:aws:rds:us-east-1:770203350335:snapshot:rds:some-snapshot-name
        
       # or...
       
       # Example 2)
       sh main.sh delete-stack profile=default landscape=mylandscape1
           # Wait until deletion is finished...
       sh main.sh create-stack \
        profile=default \
        landscape=mylandscape2 \
        rds_snapshot_arn=arn:aws:rds:us-east-1:770203350335:snapshot:rds:some-snapshot-name \
        instance_to_replace=kuali-oracle-mylandscape1
      
      
      ```
   
      **"Orphaning" contingencies:** You can replace an rds instance in one shot as in example 1 above, or in two separate steps as in example 2.
      In both examples, an `"instance_to_replace"` parameter is involved *(although you don't see it in example one, it is set dynamically).*
      This parameter indicates the `"DbInstanceIdentifier"` value of the rds database that is deleted and for which you intend the new database to replace. Its value is used for a `"Replaces"` tag set against the new rds database. Soon after the new rds database is created, an eventbridge rule will detect it and trigger a lambda function to restore route53 and security group relationships existing application stacks may have had with the deleted rds database. *NOTE: before the eventbridge rule has a chance to run, there will be a short period of time when applications stacks will be without a database - **"orphaned"**.*
      Without the `instance_to_replace` tag, any replacement rds database would have to have to be associated manually with client app stacks:
   
      1. The replacement database may have a different private endpoint *`(ie: "kuali-oracle-stg.clb9d4mkglfd.us-east-1.rds.amazonaws.com")`* than the database it replaces. In this case, each route53 CNAME record associated with the prior (deleted) rds database now "points" to a defunct private endpoint address and would need to be updated to the replacement database private endpoint.
      2. When an application stack is created and details are provided for either an existing rds database or for creation of a new one, an rds database vpc security group ID is involved as one of the parameters. At least two `"AWS::EC2::SecurityGroupIngress"` resources are created against this security group adding ingress from both the application ec2 instances and the application load balancer.
   
3. **Monitor stack progress:**
   Go to the stack in the [AWS Console](https://console.aws.amazon.com/cloudformation/home?region=us-east-1). Click on the new stack in the list and go to the "Events" tab.
   Watch for failures (these will show up in red).

4. **Obtain the master user password:**

   ```
   # Example:
   sh main.sh get-password landscape=ci profile=default
   
   # NOTE: If you ever have to delete the secret, this is how:
   aws secretsmanager delete-secret --secret-id kuali/sb/kuali-oracle-rds-admin-password --force-delete-without-recovery
   ```

5. **[Optional] Test connect to the new rds instance**
   At this point, If you did not use the `"db_snapshot_arn"` parameter, the RDS database is empty and has no schemas, but you should be able to connect to it from your computer.
   [Instructions...](jumpbox/README.md)

6. **[Optional] Perform data migration**
   If you used the `"db_snapshot_arn"` parameter for stack creation, you are finished. Otherwise, creating and populating schemas is next.
   [Instructions...](migration/README.md)
