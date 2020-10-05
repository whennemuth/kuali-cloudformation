## RDS Schema Migration

Migrate data from a source oracle kuali database schema to an empty target kuali schema of a RDS database instance. 
The AWS Data Migration Service (DMS) is used.

This documents performing an oracle [homogenous migration](https://aws.amazon.com/dms/#Homogeneous_Database_Migrations), and while homogenous migrations can technically be started with a blank target database and be configured to create tables at the target database on the fly, the following is also true

> ”DMS takes a minimalist approach and creates only those objects required to efficiently migrate the data. In other words, AWS DMS creates tables, primary keys, and in some cases unique indexes, but doesn’t create any other objects that are not required to efficiently migrate the data from the source. For example, it doesn’t create secondary indexes, non primary key constraints, or data defaults”.

Therefore this migration assumes that the target RDS database has been part of an [AWS Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html) stage.
This prior step is documented [here](../sct/README.md).


### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **AWS Session Manager Plugin**
  This plugin allows the AWS cli to launch Session Manager sessions with your local SSH client. The Version should be should be at least 1.1.26.0.
  Install instructions: [Install the Session Manager Plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered, including [IAM permissions needed to use AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.IAMPermissions).
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)
- **AWS Schema Conversion Tool:**
  This is a desktop app that can be downloaded from this link: [Installing, Verifying, and Updating the AWS Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Installing.html)
- **[SQL Developer](https://www.oracle.com/tools/technologies/whatis-sql-developer.html)** (or similar Oracle database IDE)
  This is a desktop app that can be downloaded from oracle:  [SQL Developer Download](https://www.oracle.com/tools/downloads/sqldev-downloads.html)
- **Oracle User:**
  A user that can access the source database on behalf of DMS service and has been granted enough privileges to perform the migration.
  The DBA can set this user up. The privileges are detailed here:
  - [What are the permissions required for AWS DMS when using Oracle as the source endpoint?](https://aws.amazon.com/premiumsupport/knowledge-center/dms-permissions-oracle-source/)
  - [Using an Oracle database as a source for AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.Oracle.html)
  

### Steps:

1. **Create the Secrets Manager stack (if not already exists):**
   It is better for secrets in secrets manager to be created in their own stack as these may be consumed by resources from multiple other stacks and it is therefore best to separate concerns.
Instructions: [Kuali secrets stack creation](../../../kuali_secrets/README.md)
   
2. **Create the DMS stack:**
   This step involves invoking the cloud formation service to create a DMS stack comprising:

   - [Replication instance](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.html)
   - [Source and target endpoints](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Endpoints.html)
   - [Replication task](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.html)(s)
   - [Security groups](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.Network)
   - [Subnet groups](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.VPC.html#CHAP_ReplicationInstance.VPC.Subnets)
   - [Associated IAM roles](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.IAMPermissions)

   There are dozens of parameters that the cloud formation stack needs, some of which have default values, many do not.
   For those wishing to quickly create the stack and not have to get absorbed into the task of becoming familiar with these parameters and looking up values for those representing [ARNs](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html) for existing cloud resources (like subnets), a helper script has been created.
   This helper script will perform lookups based on the AWS account and the landscape provided.
   Therefore, a minimal stack creation invocation will look like this:

   ```
   cd kuali_rds/migration/dms
   sh main.sh create-stack profile=default landscape=ci
   ```

   One parameter you might consider overriding is  `"replication_instance_class"`. If you increase the class of the replication instance (defaults to `"dms.r4.large"`, you are increasing the resources (cpu, memory, throughput, etc) of what is essentially an ec2 instance, and concurrency is increased to have more database tables populated in parallel:

   ```
   cd kuali_rds/migration/dms
   sh main.sh create-stack profile=default landscape=ci replication_instance_class=dms.r4.2xlarge
   
   # Or if updating the stack to increase the instance class:
   sh main.sh update-stack profile=default landscape=ci replication_instance_class=dms.r4.2xlarge
   ```

      

3. **Monitor stack progress:**
   Go to the stack in the [AWS Console](https://console.aws.amazon.com/cloudformation/home?region=us-east-1). Click on the new stack in the list and go to the "Events" tab.
   Watch for failures (these will show up in red).

4. **Pre-Migration Assessment:**
   This step involves using helper scripts to invoke a [Premigration Assessment](https://aws.amazon.com/about-aws/whats-new/2020/07/aws-database-migration-service-now-supports-enhanced-premigration-assessments/). This will trigger:

      - A source database endpoint connection test
      - A target database endpoint connection test
      - The premigration assessment

   ```
   cd kuali_rds/migration/dms
   sh main.sh pre-migration-assessment profile=default landscape=ci
   ```

   Once triggered, you can wait for the output to indicate results and/or log into the [AWS Console for DMS tasks](https://console.aws.amazon.com/dms/v2/home?region=us-east-1#tasks) and watch the progress of the assessment.
   
5. **Migrate the data:**
   You can either start a migration from the [AWS Console for DMS tasks](https://console.aws.amazon.com/dms/v2/home?region=us-east-1#tasks) by clicking on the task and selecting `"Actions > Restart/Resume"` or, use a helper script:

   ```
   cd kuali_rds/migration/dms
   sh main.sh migrate profile=default landscape=ci
   ```

   The default migration task type is "start-replication", but you can override this with one of the other two values:

   - resume-processing
   - reload-target

   Example:

   ```
   cd kuali_rds/migration/dms
   sh main.sh migrate profile=default landscape=ci task_type=resume-processing
   ```

   See: [StartReplicationTask - StartReplicationTaskType](https://docs.aws.amazon.com/dms/latest/APIReference/API_StartReplicationTask.html#DMS-StartReplicationTask-request-StartReplicationTaskType)   

6. NEXT