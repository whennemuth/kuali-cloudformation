## Triggered Events For Kuali RDS Database Replacement

#### Overview:

This stack creates a handful of resources that together monitor the for the creation and deletion of RDS databases for the kuali research application.
When a new database is created, that event is captured by an event bridge event rule, which in turn calls a lambda function that completes security group ingress allowances for the RDS database.

#### Problem:

The most typical sequence of events for creation of a full kuali-research environment is database stack first and application stack(s) second.
It is expected, in most cases, that the database pre-exists the application stack. For this reason, the database cannot "know" or be told what application security groups from which ingress is to be allowed. This is because at the time the database is being cloud-formed, those security groups don't exist yet. When the application stack(s) are being cloud-formed, the ID of the already existing vpc-security-group of the database is provided as a parameter, which is used to add ingress rules for the application security group(s) being created on to the already existing vpc-security-group of the RDS database.
If at some point in the future, the RDS database is re-created, those ingress rules are lost and the application loses access to the database.

#### Solution:

In order to solve this problem, it is necessary to "re-introduce" the vpc-security-group of the RDS database to the application stack via a stack update. 
The update is performed by passing all the same parameter values, except for the new vpc-security-group of the RDS database.
This can be done manually, though this would be a breach in automation and would be an added step that one would have to remember to take to avoid trouble, disruptions in service that aren't immediately obvious as to the cause.
To maintain automation, the eventbridge/lambda combination is created above to trigger the stack update(s) automatically.

Links:

https://stackoverflow.com/questions/34990104/rds-endpoint-name-format



#### **TODO:**

The "Solution" as presented above won't work as explained in [Issues](./Issues.md).
The app needs refactoring and abandonment of using stack updates, in favor of adding the ingress rules back directly.

**Refactoring:**
Base the lifecycle record keeping on security group events:

- AuthorizeSecurityGroupIngress
- CreateSecurityGroup
- DeleteSecurityGroup

Add S3 objects upon AuthorizeSecurityGroupIngress events that are named after the "Referenced" security groups (ec2, elb, batch).
Inside the object should be something like this:

```
{
	"LastRdsVpcSecurityGroupId": "sg-1234567890"
	"RdsDatabaseName": "kuali-oracle-stg"
}
```

1. When the ecs or batch stack is created or updated, the `AWS::EC2::SecurityGroupIngress` resource is created and the `AuthorizeSecurityGroupIngress` event rule is triggered. The event data captured by the lambda function will have the "Referenced" and RdsVpcSecurityGroupId security group ids in it, the latter of which should be enough to figure out what RDS instance uses it.
   Save the RdsVpcSecurityGroupId and the RDS database name into the s3 object.
   *(The RdsDatabaseName value contains the landscape in it, but consider including the baseline value into the s3 file and using it later as well.)*
2. When the RDS database is deleted, the `AWS::EC2::SecurityGroupIngress` resources will have been orphaned.
   However, once recreated, the `CreateSecurityGroup` event will be sent to the lambda function.
   Write code that determines if the created security group is applied to an kuali RDS instance and if so, cycle through each object in the S3 folder for one whose content indicates the same RdsDatabaseName *(and baseline?)*.
   If found, verify that the LastRdsVpcSecurityGroupId value refers to a security group that no longer exists.
   Then replace the value with the new security group id.
   Finally, reapply the security group ingress rules to the new RdsVpcSecurityGroup, using the name of the identified s3 file as the "referenced" security group.
3. If the application or batch stack is deleted, the `DeleteSecurityGroup` event will be sent to the lambda function.
   If the id of the deleted security group matches the name of any file in the S3 bucket, delete that file.

This refactoring will eliminate the requirement for capturing database events with cloudwatch and simplifies the lifecycle recordkeeping to one folder (created, pending and final) can be removed and all files placed in the root bucket folder.

***NOTE**: This will leave the app and batch stacks with some drift, since their orphaned ingress resources have not undergone any correction to reflect the new RdsVpcSecurityGroup, and the parameter that indicates the id of that security group will still show the old value. Will running a manual update with the admin user correct the drift? Or will the update "collide" with the externally create ingress rules?*