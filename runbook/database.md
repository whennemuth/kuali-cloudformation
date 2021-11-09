## Database migration:

This is a sequencing of steps involved in migrating the kuali-research oracle database from its current aws account to the "Common security services" aws account. 

**Terms:**

- **Legacy:** Refers to the source aws account that we are migrating from.
- **CSS:** Refers to the "Common Security Services" aws account that we are migrating to.

#### 

![](C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\runbook\database.png)

#### RUNBOOK:

1. **Create empty legacy RDS Database**
   Cloudform a new blank RDS database in the legacy account: [RDS Stack Documentation](..\kuali_rds\README.md)
   
2. **Create DMS Service**
   Create a new [AWS data migration service](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html) stack: [DMS Stack Documentation](..\kuali_rds\migration\dms\README.md)
   
3. **Create Schemas/Structure creation sql**
   Create sql DDL scripts using the [AWS Schema Conversion tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html). These will be run later against the new RDS database to create all the schemas, tables, roles, and views: [Schema Conversion Tool Documentation](..\kuali_rds\migration\sct\README.md)
   
4. **Run Schemas/Structure creation sql**
   Execute helper script to run all the generated DDL sql files against the new RDS database, and disable all triggers and constraints to avoid data migration glitches later on: [Helper script documentation](..\kuali_rds\migration\sct\docker-oracle-client\README.md)
   
5. **Migrate data**
   Start the database migration service (May take a few hours) to complete the initial data load. 
   [Change data capture](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) (CDC) is enabled so that the two databases remain in sync.

6. **[CUTOVER-ONLY] Quarantine the legacy database**
   You may at this point be moving in to a testing phase and just need a snapshot of the synchronized RDS database to share into the CSS account.
   However, if you are instead in the cutoff window, now is the time to isolate the legacy database. This means preventing any ingress. This can be done in one of three ways:

   - Stop the ec2 instances the legacy databases are running on.
   - Remove all ingress rules on the legacy database security group for port 1521.
      The ingress rules for the DMS replication instance CIDR can be exempted from this in order to avoid the replication task from kicking up a fuss about losing connectivity on its source endpoint.
   - Quiet the Kuali Research application.
      This will prevent ingress from any snaplogic origin point, but all SAP, BW, or ETL scheduled activity should be put on hold.
      Do one of the following:
      - Stop the kuali-research docker containers on the EC2 application hosts.
      - Stop the EC2 application hosts.

   Why do this? Any snapshot produced for the CSS account RDS instance should remain an exact data duplicate of the legacy database, which will not happen if the legacy database is allowed to "drift" due to further activity against it.
   
7. **Check the DMS replication task status:**
   Ensure the data migration task is in an "ok" status and the [Change data capture](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) has not errored out or stopped for any reason.

8. **Snapshot legacy RDS database**
   Take a manual snapshot of the legacy RDS database for sharing across to the CSS account. This can be done in the aws management console. Alternatively you can use the aws cli.

9. **Share the RDS snapshot**
   Share the recently taken RDS snapshot with the CSS account. Once this has been done, the snapshot will show up in that account in the management console in the "shared with me" tab of the RDS snapshots view.

10. **Create CSS RDS database**
   Cloudform a new RDS database based on the snapshot that was shared: [RDS Stack Documentation](..\kuali_rds\README.md)
   If an RDS database for the same environment already exists having been used for testing, it must be deleted first.

11. **Re-enable triggers and constraints**
   Use the [helper script](..\kuali_rds\migration\sct\docker-oracle-client\README.md) to enable all triggers and constraints against the new RDS database. The clone snapshot was taken against a primary RDS database whose triggers and constraints were disabled. Why were they disabled? Data migration between source and target databases has been found to encounter errors if triggers and constraints are not disabled. The source application performs additions and updates in the proper sequence, however, the migration process does not follow an specific order, hence constraint/trigger problems.

12. **Update sequences**
   Use the [helper script](..\kuali_rds\migration\sct\docker-oracle-client\README.md) to update sequences on the new RDS database. Why is this necessary? The ongoing migration [Change data capture](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) (CDC) process keeps all data in sync, but not the sequences that produce unique numbers for primary key fields. CDC keeps these primary key field in sync, but the corresponding sequences need to be "caught up" in the target database to avoid primary key constraint violation that are sure to occur if the sequences are left as is.
   **IMPORTANT!**: The legacy EC2-hosted database, if shutdown, needs to be turned back on for the sequence update process to work.

