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

   If stopped, restart or reload it to get back up to sync:

   ```
   cd kuali_rds/migration/dms
   
   # Resume
   sh main.sh migrate profile=legacy landscape=stg task_type=resume-processing
   
   # Reload
   sh main.sh migrate profile=legacy landscape=stg task_type=resume-reload-target
   ```

1. **Stop the DMS migration task:**
   If the replication task shows 100% progress with no issues, stop it.

   ```
   cd kuali_rds/migration/dms
   sh main.sh stop-task profile=legacy landscape=stg 
   ```
   
1. **Shut down the legacy environment:**
   Turn off the staging application ec2 instances, followed by the database ec2 instances:

   ```
   aws --profile=legacy ec2 stop-instances --instance-ids i-090d188ea237c8bcf i-0cb479180574b4ba2
   
   aws --profile=legacy ec2 stop-instances --instance-ids i-0a10357e09f87c2b5 i-0ec7d772f6d22d33c
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
           Key=Baseline,Value=stg \
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
   cd kuali_rds && \
   sh main.sh create-stack \
     profile=infnprd \
     landscape=stgtemp \
     rds_snapshot_arn=arn:aws:rds:us-east-1:730096353738:snapshot:kuali-stg-$(date +'%m-%d-%y')
   ```

6. **Re-enable primary & foreign keys:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh toggle-constraints-triggers \
     profile=infnprd \
     landscape=stgtemp \
     baseline=stg \
     toggle_constraints=enable \
     toggle_triggers=enable \
     dryrun=true
     
   # UPDATE! The following does not work if the stored proc takes a long time. The db client driver fails with:
   # "end-of-file" hangup notice on the connection and the data gets into a bad and unreversible state.
   # So, go to sqldeveloper and execute the stored procs manually:
   
   execute admin.toggle_constraints('KCOEUS', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('KCOEUS', 'FK', 'ENABLE');
   /
   execute admin.toggle_constraints('KCRMPROC', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('KCRMPROC', 'FK', 'ENABLE');
   /
   execute admin.toggle_constraints('KULUSERMAINT', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('KULUSERMAINT', 'FK', 'ENABLE');
   /
   execute admin.toggle_constraints('SAPBWKCRM', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('SAPBWKCRM', 'FK', 'ENABLE');
   /
   execute admin.toggle_constraints('SAPETLKCRM', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('SAPETLKCRM', 'FK', 'ENABLE');
   /
   execute admin.toggle_constraints('SNAPLOGIC', 'PK', 'ENABLE');
   /
   execute admin.toggle_constraints('SNAPLOGIC', 'FK', 'ENABLE');
   
   
   execute admin.toggle_triggers('KCOEUS', 'ENABLE');
   /
   execute admin.toggle_triggers('KCRMPROC', 'ENABLE');
   /
   execute admin.toggle_triggers('KULUSERMAINT', 'ENABLE');
   /
   execute admin.toggle_triggers('SAPBWKCRM', 'ENABLE');
   /
   execute admin.toggle_triggers('SAPETLKCRM', 'ENABLE');
   /
   execute admin.toggle_triggers('SNAPLOGIC', 'ENABLE');
   /
     
   # Spot check results. Output of these queries should be the same in legacy and css databases:
   
   select count(*)
   from sys.all_constraints 
   where constraint_type = 'R'
       and owner in ('KCOEUS', 'KCRMPROC', 'KULUSERMAINT', 'SAPBWKCRM', 'SAPETLKCRM', 'SNAPLOGIC')
       and status = 'DISABLED'; 
       # and status = 'ENABLED';
   
   # Confirm the remaining number of disabled triggers is the same between legacy and css databases by running the following on both
   select count(*)
   from sys.all_triggers
   WHERE
       status = 'DISABLED' and
       # status = 'ENABLED' and
       owner in ('KCOEUS', 'KCRMPROC', 'KULUSERMAINT', 'SAPBWKCRM', 'SAPETLKCRM', 'SNAPLOGIC');
   ```

5. **Update sequences:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client && \
   sh dbclient.sh update-sequences \
     target_aws_profile=infnprd \
     legacy_aws_profile=legacy \
     baseline=stg \
     landscape=stgtemp \
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
     landscape=stgtemp \
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
       --db-instance-identifier $(nameFromARN $(getRdsArn 'stgtemp')) \
       --db-snapshot-identifier kuali-stg-$(date +'%m-%d-%y') \
       --tags \
           Key=Function,Value=kuali \
           Key=Service,Value=research-administration \
           Key=Baseline,Value=stg \
           Key=Landscape,Value=stg
   ```

8. **Inventory database ingress rules:**
   Save off the output of the following to a file named after the rds db security group* (will be referenced in a later step)*:

   ```
   cd scripts/
   source common-functions.sh
   export AWS_PROFILE=infnprd
   
   sg_id=$(
       aws rds describe-db-instances \
       --db-instance-id $(getRdsArn stg) \
       --output text \
       --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'
   )
   aws ec2 describe-security-groups \
   	--group-ids $sg_id \
   	--query 'SecurityGroups[0].IpPermissions' > ${sg_id}.txt
   ```

8. **Restore the staging database:**
   Restore the current "stg" RDS database from the snapshot created from the "stg-temp" database:

   ```
   cd scripts/
   source common-functions.sh
   
   # NOTE modified stack parameter(s) should be the last name=value pair(s).
   ( \
   	runStackTweak \
   		kuali-rds-oracle-stg \
   		prompt=true \
   		landscape=stg \
   		profile=infnprd \
   		dryrun=true \
   		RdsSnapshotARN=arn:aws:rds:us-east-1:770203350335:snapshot:kuali-stg-$(date +'%m-%d-%y') \
   )
   ```

9. **Delete the temp RDS database:**

   ```
   cd kuali_rds/
   sh main.sh delete-stack profile=infnprd landscape=stgtemp
   ```

11. **Ensure security group updates:**
    Having restored the staging database, check that it still retains all of the ingress rules it had before the restore was performed.
    If you see a different vpc-security-group-id for the rds instance, then ingress rules are missing. The "UserIdGroupPairs" section of the output obtained earlier will have the missing details.
    *SAMPLE OUTPUT FOR PROD:*

    ```
            "UserIdGroupPairs": [
                {
                    "Description": "Allows ingress to an rds instance created in another stack from application ec2 instances created in this stack.",
                    "GroupId": "sg-095c2b4a977ba019c",
                    "UserId": "115619461932"
                },
                {
                    "Description": "Allows ingress to an rds instance created in another stack from the alb created in this stack.",
                    "GroupId": "sg-0e4292d2c46bfa8cc",
                    "UserId": "115619461932"
                },
                {
                    "Description": "Allows ingress to an rds instance created in another stack by any resource in the compute environment security group created in this stack.",
                    "GroupId": "sg-0f009b48e3e58b21f",
                    "UserId": "115619461932"
                }
            ]
    
    ```

    To restore these ingress rules, do so through stack updates to the related stacks that created them in the first place.
    This will prevent drift in those stacks that gets introduced if you do things manually.
    To restore ingress for the first two security groups (alb and ec2), perform an application stack update:

    ```
    cd scripts/
    source common-functions.sh
    export AWS_PROFILE=infnprd
    
    sg_id=$(
        aws rds describe-db-instances \
        --db-instance-id $(getRdsArn stg) \
        --output text \
        --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'
    )
    
    # NOTE modified stack parameter(s) should be the last name=value pair(s).
    (
    	runStackTweak \
    		kuali-ecs-stg \
    		prompt=true \
    		landscape=stg \
    		dryrun=true \
    		RdsVpcSecurityGroupId=${sg_id}
    )
    
    (
    	runStackTweak \
    		research-admin-reports \
    		prompt=true \
    		landscape=stg \
    		dryrun=true \
    		RdsVpcSecurityGroupId=${sg_id}
    )
    ```

    

12. **Force refresh of ecs cluster:**

    ```
    aws --profile=infnprd ecs update-service \
      --cluster kuali-ecs-stg-cluster \
      --service kuali-research \
      --force-new-deployment
    ```

    Wait until the update is complete and you can visit the service in the browser.
    
15. **Create redirect for legacy staging:**
    Create the stack

    ```
    cd kuali_maintenance
    sh main.sh create-stack landscape=stg profile=legacy
    ```

    Swap out the old ec2 pair with the new small ec2 that serves up the redirect page:

    ```
    cd kuali-maintenance
    sh main.sh elb-swapout landscape=stg profile=legacy
    ```

16. **Update the ticket and email the team:**
    "*Hi Team.*
    *The kuali "cutover" for the staging environment aws infrastructure has been completed:*

    1) *The existing staging oracle database has been snapshotted and the ec2 instances it runs on are shut down*
    2) *The RDS database in the new environment has been "rebased" on the snapshot.*
    3) *The old staging kc url now presents a page referring users to the new location.*
    4) *The new location is https://stg.kualitest.research.bu.edu/dashboard*

    *The remaining items for the overall migration are as follows:*

    1) *Client services of the kuali app and/or database (SAP, informatica, snaplogic) update their configurations to "officially" reference the new staging location, endpoints and authentication details. Each client has a child ticket in [parent ticket] for their effort in this.*
    2) *The carry all regression testing/fixing to completion.*
    3) *Scheduling of a repeat exercise for the production environment after a period of "observation".*

    *Thanks,*
    *Warren*"

