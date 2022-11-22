## Issues with stack updates

#### Overview

There were a few issues encountered with the operation of this stack that require the cloud-forming to be done a certain way, and in order to clarify why a seemingly more obvious approach wasn't taken, the alternative is covered here with context sufficient to explain it as a workaround.

#### Manual Operation:

The main purpose of this stack is to setup a lambda function that adds ingress rules to an RDS database security group. The rds database was created in **stack A**, but is being replaced and will lose certain ingress rules that were added AFTER it had been originally created. That was done as part of the subsequent cloud-forming of an application stack, **stack B**, which is was given the id of the RDS database vpc security group to work with.
The obvious way to accomplish this restoration task, if one were performing it manually, would be to perform an update on **stack B**, providing the new RDS database vpc-security-group-id value as the only modified parameter.

This will work if one remembers to perform the stack updates manually if an RDS database used by an application stack is ever re-cloud-formed, and understands the context around what they are doing.

#### Automated Operation:

The more desirable approach is to have lambda perform the manual step automatically via an event-bridge trigger.
Originally, work went into making the lambda function perform the stack update itself, duplicating the manual step. However, the stack update would always proceed up to a point, encounter an error, and finally roll back.
The difference between an IAM user manually updating an application stack to success, and a lambda function performing the same update to failure, is the role each is using:

- IAM User: Admin role with unlimited privileges
- Lambda: Custom created role sufficient to perform s3 lookups, modify DNS records, and invoke cloud-formation updates.

The lambda role, while enough to trigger a stack update, does not have sufficient policies satisfy the needs of actions that occur within the update itself.
One or more of the nested stacks fails with "Internal Failure" as the message, which can be traced in cloudtrail to a !GetAtt failure, but with no specifics.
!GetAtt has a 2 minute timeout, and it seems that a stack will remain in a "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" state for a VERY long time (over a day) before it proceeds to a fully rolled back state and ready to accept more updates.

From this, one can see that trial and error is not an option - simply adding to the role the lambda function uses until the error goes away would take far too long.

Before discussing what would seem the obvious remedies, it important to review the "RoleARN" parameter in [Update Stack](https://docs.aws.amazon.com/AWSCloudFormation/latest/APIReference/API_UpdateStack.html):

> "*The Amazon Resource Name (ARN) of an AWS Identity and Access Management (IAM) role that AWS CloudFormation assumes to update the stack. AWS CloudFormation uses the role's credentials to make calls on your behalf. AWS CloudFormation **always uses this role for all future operations** on the stack. Provided that users have permission to operate on the stack, AWS CloudFormation uses this role even if the users don't have permission to pass it. Ensure that the role grants least privilege.*
>
> ***If you don't specify a value, AWS CloudFormation uses the role that was previously associated with the stack. If no role is available, AWS CloudFormation uses a temporary session that is generated from your user credentials.***"

From this, 3 scenarios are possible:

1. No RoleArn value is provided when creating the stack. No RoleArn is provided when updating the stack.
   *"CloudFormation uses a temporary session that is generated from your **user credentials**"*.
2. A RoleArn is provided when updating the stack *(regardless of whether or not one was specified when creating the stack)*.
   *"CloudFormation uses the **role's credentials** to make calls on your behalf"*
3. A RoleArn is provided when creating the stack. No RoleArn is provided when updating the stack.
   *"CloudFormation uses the **role that was previously associated with the stack**"*

Up to this point, cloud-formation has been passed credentials for updates *(executed either by an IAM principal to success, or the lambda function to failure)*, per scenario 1 above. RoleArn is never specified.

Other options?

- **Trial and error *(scenario 2)***
  As discussed above, the nature of the errors preclude exact details as to what fails and the stack remains in a "stuck" state for far too long for trials that include adding to the security group used by the lambda and starting again. The same applies to crafting a custom role and trying to guess what should be in it to for it to work while still adhering too "least privilege". 
  This leads to an additional problem in that, per the RoleARN parameter rules above, this role would be permanently associated with the stack.
  If a user whose credentials come from an admin role performs a subsequent update (and does not pass an explicit RoleARN value) their credentials would be ignored and the role associated with the stack would be used by cloudformation to perform the update. This is problematic if the user is performing a different kind of update that requires their admin privileges work. Also, the only way to reverse this is to use the RoleARN parameter in the manual stack update to override the associated role. The next scenario explains why this is impossible. 
- **For updates, using the RoleARN parameter, let lambda "borrow", the admin role associated with the credentials that were in use by the iam principal at the time they created the stack.**
  The "Shibboleth-InfraMgt" or "Shibboleth-CFarchitect" roles *(admin)* cannot be given to a lambda function since their trust policy that requires the principal to be assuming the role through saml authentication via federated access.
  What's more is that a lambda function should not be given unlimited access. 
- **Create an admin role for lambda to use for stack updates, using the RoleARN parameter.**
  This is bad practice. A lambda function should not be given unlimited access.
- **Give up on cloud formation, and have the lambda function add the ingress rules directly.**
  This seems to be the only option left over. It will result in an acceptable form of drift in the application stacks in the form of uncoordinated ingress rule resources replacements.

Therefore, the last option above is the one this stack uses.