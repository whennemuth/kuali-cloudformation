## RDS Schema Migration

Migrate data from a source oracle kuali database schema to an empty target kuali schema of a RDS database instance. 



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

### Steps:

*”DMS takes a minimalist approach and creates only those objects required to efficiently migrate the data. In other words, AWS DMS creates tables, primary keys, and in some cases unique indexes, but doesn’t create any other objects that are not required to efficiently migrate the data from the source. For example, it doesn’t create secondary indexes, non primary key constraints, or data defaults”.*

```
set serveroutput on; 
declare 
  V_TABL_NM ALL_TABLES.TABLE_NAME%TYPE; 
  ROW_COUNT INT;
    
BEGIN 
    FOR GET_TABL_LIST IN ( 
        SELECT TABLE_NAME FROM ALL_TABLES 
        WHERE TABLESPACE_NAME = 'KUALI_DATA' AND OWNER = 'KCOEUS'   
        ORDER BY TABLE_NAME
    )LOOP 
        V_TABL_NM := GET_TABL_LIST.TABLE_NAME;
        EXECUTE IMMEDIATE 'select count(*) from "' || V_TABL_NM || '"' INTO ROW_COUNT;
        DBMS_OUTPUT.PUT_LINE(V_TABL_NM || ': ' || ROW_COUNT);
    END LOOP; 
END;
```

