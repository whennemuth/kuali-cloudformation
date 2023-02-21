## PRODUCTION RELEASE RUNBOOK FOR CLI

#### <img align="left" src="C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\runbook\checklist-release.png">Kuali Research "release night" migration to common security services aws account.

This is the sequencing of work and assignments that will go into transitioning the kuali research application stack to the common security services (CSS) account for the production envionment and retiring the current aws cloud account where it is currently running.

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
     --filter Name=replication-task-id,Values=kuali-dms-oracle-prod-dms-replication-task \
     --query 'ReplicationTasks[].{status:Status, percent:ReplicationTaskStats.FullLoadProgressPercent}'
   ```

   If stopped, restart or reload it to get back up to sync:

   ```
   cd kuali_rds/migration/dms
   
   # Resume
   sh main.sh migrate profile=legacy landscape=prod task_type=resume-processing
   
   # Reload
   sh main.sh migrate profile=legacy landscape=prod task_type=resume-reload-target
   ```

1. **Stop the DMS migration task:**
   If the replication task shows 100% progress with no issues, stop it.

   ```
   cd kuali_rds/migration/dms
   sh main.sh stop-task profile=legacy landscape=prod 
   ```
   
1. **Put up a "down for maintenance" page:**
   Create the stack

   ```
   cd kuali_maintenance
   sh main.sh create-stack landscape=prod profile=legacy image_tag=down
   ```
   
   Swap out the old ec2 pair with the new small ec2 that serves up the redirect page:
   
   ```
   cd kuali_maintenance
   sh main.sh elb-swapout landscape=prod profile=legacy
   ```
   
   Lastly, verify in the browser that all links for kuali now bring up a "down for maintenance" page.
   
1. **Shut down the legacy environment:**
   Turn off the production application ec2 instances, followed by the database ec2 instances:

   ```
   aws --profile=legacy ec2 stop-instances --instance-ids i-0534c4e38e6a24009 i-07d7b5f3e629e89ae
   
   aws --profile=legacy ec2 stop-instances --instance-ids i-056cffe470fee2792 i-024246073db181f34
   ```
   
2. **Fresh database snapshot**
   Create a snapshot of the legacy account migration target RDS database:

   ```
   aws --profile=legacy rds create-db-snapshot \
       --db-instance-identifier kuali-oracle-prod \
       --db-snapshot-identifier kuali-prod-$(date +'%m-%d-%y') \
       --tags \
           Key=Function,Value=kuali \
           Key=Service,Value=research-administration \
           Key=Baseline,Value=prod \
           Key=Landscape,Value=prod
   ```

   Once the snapshot is created, share it to the CSS account:

   ```
   aws --profile=legacy rds modify-db-snapshot-attribute \
     --db-snapshot-identifier kuali-prod-$(date +'%m-%d-%y') \
     --attribute-name restore \
     --values-to-add 115619461932
   ```

3. **Create interim database from shared snapshot:**
   In the target CSS account, spin up an temporary database based on the shared snapshot.

   ```
   cd kuali_rds && \
   sh main.sh create-stack \
     profile=infprd \
     landscape=prodtemp \
     rds_snapshot_arn=arn:aws:rds:us-east-1:730096353738:snapshot:kuali-prod-$(date +'%m-%d-%y')
   ```

7. **Re-enable primary & foreign keys:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh toggle-constraints-triggers \
     profile=infprd \
     landscape=prodtemp \
     baseline=prod \
     toggle_constraints=enable \
     toggle_triggers=enable \
     dryrun=true
     
   # UPDATE! The following does not work if the stored proc takes a long time. The db client driver fails with:
   # "end-of-file" hangup notice on the connection and the data gets into a bad and unreversible state.
   # So, go to sqldeveloper and execute the stored procs manually:
   
   # User: admin
   # Password: [secrets manager: kuali/prod/kuali-oracle-rds-admin-password]
   # hostname: [look for the "endpoint" value in the rds console for the new instance (no bu dns entry exists)]:
   
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
     target_aws_profile=infprd \
     legacy_aws_profile=legacy \
     baseline=prod \
     landscape=prodtemp \
     template_bucket_name=kuali-research-ec2-setup \
     dryrun=true
   ```

6. **Compare table counts [optional]:**

   ```
   cd kuali_rds/migration/sct/docker-oracle-client
   sh dbclient.sh compare-table-counts \
     target_aws_profile=infprd \
     legacy_aws_profile=legacy \
     baseline=prod \
     landscape=prodtemp \
     template_bucket_name=kuali-research-ec2-setup \
     dryrun=true
   ```

7. **Snapshot the RDS database:**
   The CSS and Legacy databases should now be identical. Create a snapshot.

   ```
   cd scripts/
   source common-functions.sh
   export AWS_PROFILE=infprd
   
   aws rds create-db-snapshot \
       --db-instance-identifier $(nameFromARN $(getRdsArn 'prodtemp')) \
       --db-snapshot-identifier kuali-prod-$(date +'%m-%d-%y') \
       --tags \
           Key=Function,Value=kuali \
           Key=Service,Value=research-administration \
           Key=Baseline,Value=prod \
           Key=Landscape,Value=prod
   ```

8. **Inventory database ingress rules:**
   Save off the output of the following to a file named after the rds db security group* (will be referenced in a later step)*:

   ```
   cd scripts/
   source common-functions.sh
   export AWS_PROFILE=infprd
   
   sg_id=$(
       aws rds describe-db-instances \
       --db-instance-id $(getRdsArn prod) \
       --output text \
       --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'
   )
   aws ec2 describe-security-groups \
   	--group-ids $sg_id \
   	--query 'SecurityGroups[0].IpPermissions' > ${sg_id}.txt
   ```

8. **Restore the production database:**
   Replace the existing prod rds database stack with a new one based on the new snapshot:

   ```
   cd kuali_rds && \
   sh main.sh recreate-stack \
     profile=infprd \
     landscape=prod \
     using_route53=true \
     multi_az=true \
     rds_snapshot_arn=arn:aws:rds:us-east-1:115619461932:snapshot:kuali-prod-$(date +'%m-%d-%y')
   ```
   
   
   
9. **Delete the temp RDS database:**

   ```
   cd kuali_rds/
   sh main.sh delete-stack profile=infprd landscape=prodtemp
   ```

11. **Ensure security group updates:**
    Having restored the production database, check that it still retains all of the ingress rules it had before the restore was performed.
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
    export AWS_PROFILE=infprd
    
    sg_id=$(
        aws rds describe-db-instances \
        --db-instance-id $(getRdsArn prod) \
        --output text \
        --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'
    )
    
    # NOTE modified stack parameter(s) should be the last name=value pair(s).
    (
      runStackTweak \
        kuali-ecs-prod \
        prompt=true \
        landscape=prod \
        dryrun=true \
        RdsVpcSecurityGroupId=${sg_id}
    )
    
    (
      runStackTweak \
        research-admin-reports \
        prompt=true \
        landscape=prod \
        dryrun=true \
        RdsVpcSecurityGroupId=${sg_id}
    )
    ```

    

12. **Force refresh of ecs cluster:**

    ```
    aws --profile=infprd ecs update-service \
      --cluster kuali-ecs-prod-cluster \
      --service kuali-research \
      --force-new-deployment
    ```

    Wait until the update is complete and you can visit the service in the browser.
    
12. **Enable all 7 research admin reports event rules in the new prod account:**
    Go to the aws console at: https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/rules
    check each rule (except the "test" rule) and click "enable"
    All report recipients listed in the associated dynamodb table should start getting emails from this stack.
    
12. **Disable all 7 research admin reports event rules in the legacy prod account:**
    Perform the same steps in reverse.
    
15. **Modify the redirect for legacy production:**
    Now that the cutover is finished, change the "*`down for maintenance`*" redirect to "*`Kuali has changed location, update your shortcuts`*".
    This requires issuing a command to the ec2 instance to download and run a different docker image that serves up the page.
    
    ```
    # Update the stack to change the ImageTag parameter:
    cd kuali_maintenance
    (
      runStackTweak \
        kuali-maintenance-prod \
        landscape=prod \
        profile=legacy \
        ImageTag=latest
    )
    
    # When stack update is complete, run this to restart docker on the ec2:
    sh main.sh image-swapout landscape=prod
    ```
    
    In the browser, verify that the message has changed.
    
16. **Update the ticket and email the team:**
    "*Hi Team.*
    *The kuali "cutover" for the production environment aws infrastructure has been completed:*

    1) *The existing production oracle database has been snapshotted and the ec2 instances it runs on are shut down*
    2) *The RDS database in the new environment has been "rebased" on the snapshot.*
    3) *The old production kc url now presents a page referring users to the new location.*
    4) *The new location is https://kuali.research.bu.edu/dashboard*

    *Thanks,*
    *Warren*"

