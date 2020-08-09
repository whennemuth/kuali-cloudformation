## Kuali migration to RDS

Migrate existing kuali oracle databases to empty oracle RDS instances

### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS commandline iterface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **AWS Session Manager Plugin**
  This plugin allows the AWS cli to launch Session Manager sessions with your local SSH client. The Version should be should be at least 1.1.26.0.
  Install instructions: [Install the Session Manager Plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)
- **AWS Schema Conversion Tool:**
  This is a desktop app that can be downloaded from this link: [Installing, Verifying, and Updating the AWS Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Installing.html)
- **[SQL Developer](https://www.oracle.com/tools/technologies/whatis-sql-developer.html)** (or similar Oracle database IDE)
  This is a desktop app that can be downloaded from oracle: [SQL Developer Download](https://www.oracle.com/tools/downloads/sqldev-downloads.html)

### Steps:

1. **Read the documentation:**
   Read amazons user guide that covers what's being done in the following steps: [Converting Oracle to Amazon RDS for Oracle](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Source.Oracle.ToRDSOracle.html)

2. **Obtain the database password :**

   The target RDS database will have a master user and password.
   The RDS stack was created along with a secrets-manager secret value containing the users name and the password.
   The username is **"admin"**. To obtain the password, execute the following:

   ```
   aws --profile [your.profile] secretsmanager get-secret-value \
       --secret-id kuali/sb/oracle-rds-password \
       --output text \
       --query '{SecretString:SecretString}' \
       | jq '.MasterUserPassword' \
       | sed 's/"//g'
       
   NOTE: If you ever have to delete the secret, this is how:
   aws secretsmanager delete-secret --secret-id kuali/sb/oracle-rds-password --force-delete-without-recovery
   ```

3. **Clone this repository**:

   ```
   git clone https://github.com/bu-ist/kuali-infrastructure.git
   cd kuali-infrastructure/kuali_rds/migration
   ```

4. **Establish a tunnel to the RDS instance**
   The oracle RDS instance(s) have been deployed into a private subnet and have no public DNS. So, no database connection can be established directly, but there are ways to get around this restriction through SSH tunneling combined with port forwarding.
   is a second set of subnets for the application "layer" where the kuali app is running. These subnets are also private, but are attached to transit gateways that link the campus VPNs. You can access these





https://codelabs.transcend.io/codelabs/aws-ssh-ssm-rds/index.html#6

https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html

```
-- select * from cdb_tablespaces;
CREATE TABLESPACE KUALICO_TS_01 DATAFILE SIZE 1G AUTOEXTEND ON;

-- USER SQL
CREATE USER KUALICO IDENTIFIED BY "password"  
DEFAULT TABLESPACE "KUALICO_TS_01"
TEMPORARY TABLESPACE "TEMP";

-- QUOTAS
ALTER USER KUALICO QUOTA UNLIMITED ON KUALICO_TS_01;

-- ROLES
GRANT "CONNECT" TO KUALICO ;
ALTER USER KUALICO DEFAULT ROLE "CONNECT";

-- SYSTEM PRIVILEGES
GRANT CREATE TRIGGER TO KUALICO ;
GRANT CREATE VIEW TO KUALICO ;
GRANT CREATE SESSION TO KUALICO ;
GRANT CREATE TABLE TO KUALICO ;
GRANT CREATE TYPE TO KUALICO ;
GRANT CREATE SYNONYM TO KUALICO ;
GRANT CREATE SEQUENCE TO KUALICO ;
GRANT CREATE PROCEDURE TO KUALICO ;

```

