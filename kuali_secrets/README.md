## Kuali Secrets stack creation

It is better for secrets in [Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) to be created from their own stack as these may be consumed by resources from multiple other stacks and it is therefore best to separate concerns.

This stack is used to quickly get started with a one shot creation of a number of secrets for kuali (mostly rds db user/passwords for dms and sct).
It is not intended to add more secrets, or edit existing secrets through stack updates since it would be onerous to gather up and pass in all of the prior parameters again. Instead, additional secrets should be added through the cli or api.

Resources in other stacks can have properties that dynamically look up fields in any given secret.
Example:

`Password: !Sub '{{resolve:secretsmanager:kuali/${Landscape}/kuali-oracle-ec2-dms-password:SecretString:password}}'`

Querying the secret directly with the AWS CLI would look like this:

```
aws secretsmanager get-secret-value \
  --secret-id kuali/$Landscape/kuali-oracle-ec2-dms-password \
  --output text \
  --query '{SecretString:SecretString}' | jq '.password'
```

Adding another secret (with a random password) with the AWS CLI, would look like this:

```
landscape=sb
aws --profile=infnprd secretsmanager create-secret \
  --name "kuali/$landscape/kuali-oracle-rds-app-password" \
  --description "The application user (probably KCOEUS) and password for the kc rds $landscape database" \
  --secret-string '{
    "username": "KUALICO",
    "password": "'$(date +%s | sha256sum | base64 | head -c 16)'"
  }' \
  --tags '[
    {"Key": "Name", "Value": "kuali/'$landscape'/kuali-oracle-rds-app-password"},
    {"Key": "Service", "Value": "research-administration"},
    {"Key": "Function", "Value": "kuali"},
    {"Key": "Landscape", "Value": "'$landscape'"}
  ]'
```



### Prerequisites:

- **Git:**
  Needed to download this repository. [Git Downloads](https://git-scm.com/downloads)
- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered, including [IAM permissions needed to use AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.IAMPermissions).
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)

### Steps:

1. **Create the stack:**

   ```
   # Clone this repo:
   
   # Create the stack, with single default secret for the RDS master admin and password to be autocreated
   cd kuali/kuali_secrets
sh main.sh create-stack profile=default landscape=ci
   
   # Same as above, but also create the kc application user and password secret.
   cd kuali/kuali_secrets
   sh main.sh create-stack profile=default landscape=ci rds_app_username=KCOEUS rds_app_password=myKcoeusPassword
   
   ```
   
   