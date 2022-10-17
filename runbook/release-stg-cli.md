## STAGING RELEASE RUNBOOK FOR CLI

#### <img align="left" src="C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\runbook\checklist-release.png">Kuali Research "release night" migration to common security services aws account.

This is the sequencing of work and assignments that will go into transitioning the kuali research application stack to the common security services (CSS) account for the staging envionment and retiring the current aws cloud account where it is currently running.

This list derives from the [release.md](./release.md) runbook, but is concerned with the specifics of any and all steps that can be scripted and have api alternatives for aws management console manual steps.



### RUNBOOK TASKS:

1. **Check DMS status:**
   The ongoing replication of the DMS service might have stopped due to error. Check the status:

   ```
   aws \
     --profile=legacy \
     --region=us-east-1 \
     dms describe-replication-tasks \
     --without-settings \
     --filter Name=replication-task-id,Values=kuali-dms-oracle-stg-dms-replication-task \
     --query 'ReplicationTasks[].{status:Status, percent:ReplicationTaskStats.FullLoadProgressPercent}'
   ```

   If stopped, restart or reload it:

   ```
   cd kuali_rds/migration/dms
   
   # Resume
   sh main.sh migrate profile=legacy landscape=stg task_type=resume-processing
   
   # Reload
   sh main.sh migrate profile=legacy landscape=stg task_type=resume-reload-target
   ```

   **Database Quarantine:**
   Turn of the staging application ec2 instances:

   ```
   aws --profile=infnprd ec2 stop-instances i-090d188ea237c8bcf i-0cb479180574b4ba2
   ```

2. **Fresh database snapshot**
   Create a snapshot of the legacy account migration target RDS database:

   ```
   aws --profile=legacy rds create-db-snapshot \
       --db-instance-identifier kuali-oracle-stg \
       --db-snapshot-identifier kuali-stg-$(date +'%m-%d-%y') \
       --tags \
           Key=Function,Value=kuali \
           Key=Service,Value=research-administration \
           key=Baseline,Value=stg \
           Key=Landscape,Value=stg
   ```

   Once the snapshot is created, share it to the CSS account:

   ```
   aws --profile=legacy rds modify-db-snapshot-attribute \
     --db-snapshot-identifier kuali-stg-$(date +'%m-%d-%y') \
     --attribute-name restore \
     --values-to-add 770203350335
   ```

3. **Create interim database from shared snapshot:**
   In the target CSS account, spin up an temporary database based on the shared snapshot.

   ```
   cd kuali_rds/
   sh main.sh create-stack \
     profile=infnprd \
     landscape=stg_temp \
     rds_snapshot_arn=arn:aws:rds:us-east-1:730096353738:snapshot:kuali-stg-$(date +'%m-%d-%y')
   ```

4. **Re-enable primary & foreign keys:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh toggle-constraints-triggers \
     profile=infnprd \
     landscape=stg \
     baseline=stg \
     toggle_constraints=enable \
     toggle_triggers=enable \
     dryrun=true
     
   # Spot check results. Output of these queries should be the same in legacy and css databases:
   
   select count(*)
   from sys.all_constraints 
   where constraint_type = 'R'
       and owner in ('KCOEUS', 'KCRMPROC', 'KULUSERMAINT', 'SAPBWKCRM', 'SAPETLKCRM', 'SNAPLOGIC')
       and status = 'DISABLED'; 
       # and status = 'ENABLED';
   
   # Confirm the remaining number of disabled triggers is the same between legacy and css databases by running the following on both
   select *
   from sys.all_triggers
   WHERE
       status = 'DISABLED' and
       # status = 'ENABLED' and
       owner in ('KCOEUS', 'KCRMPROC', 'KULUSERMAINT', 'SAPBWKCRM', 'SAPETLKCRM', 'SNAPLOGIC');
   ```

5. **Update sequences:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh update-sequences \
     target_aws_profile=infnprd 
     legacy_aws_profile=legacy \
     baseline=stg \
     landscape=stg \
     template_bucket_name=kuali-research-ec2-setup \
     dryrun=true
   ```

6. **Compare table counts [optional]:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh compare-table-counts \
     target_aws_profile=infnprd \
     legacy_aws_profile=legacy \
     baseline=stg \
     landscape=stg \
     template_bucket_name=kuali-research-ec2-setup \
     dryrun=true
   ```

7. **Snapshot the RDS database:**
   The CSS and Legacy databases should now be identical. Create a snapshot.

   ```
   cd scripts/
   source common-functions.sh
   export AWS_PROFILE=infnprd
   
   aws rds create-db-snapshot \
       --db-instance-identifier $(nameFromARN $(getRdsArn 'stg_temp')) \
       --db-snapshot-identifier kuali-stg-$(date +'%m-%d-%y') \
       --tags \
           Key=Function,Value=kuali} \
           Key=Service,Value=research-administration \
           key=Baseline,Value=stg \
           Key=Landscape,Value=stg
   ```

8. **Restore the staging database:**
   Restore the current "stg" RDS database from the snapshot created from the "stg-temp" database:

   ```
   cd scripts/
   source common-functions.sh
   
   # NOTE modified stack parameter(s) should be the last name=value pair(s).
   (
   	runStackTweak \
   		kuali-rds-oracle-stg \
   		prompt=true \
   		landscape=stg \
   		profile=infnprd \
   		dryrun=true \
   		RdsSnapshotARN=arn:aws:rds:us-east-1:770203350335:snapshot:kuali-oracle-stg-new
   )
   ```

9. **Delete the temp RDS database:**

   ```
   cd kuali_rds/
   sh main.sh delete-stack profile=infnprd landscape=stg_temp
   ```

10. **Ensure security group updates:**

11. **Force refresh of ecs cluster:**