## Jenkins build & CI/CD server for Kuali research

<img align="left" src="jenkins1.png" alt="jenkins1" style="margin-right:30px;" />Jenkins is a build automation and deployment server for CI/CD pipelines. It is essentially comprised of a collection of jobs and triggers. Among the jobs performed for Kuali are:

------

- Pulling source code from github and building the java application for the research app
- Packaging the java build artifact into a docker image and exporting it to an elastic container registry.
- Performing the same steps for the other kuali services (cor-main, dashboard, pdf, reverse-proxy)
- Building application infrastructure server/cluster stacks in cloudformation, each drawing from the docker registry.

------

### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
  
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
  
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)
  
- **S3 Bucket**:
  This S3 Bucket must exist prior to stack creation and serves 2 purposes:
  
  1. You must specify (either by default or explicit entry) an S3 bucket location where the yaml template(s) are to be uploaded and referenced as a parameter for stack creation. The bucket currently defaults to the following:
  
     ```
     s3://kuali-conf/cloudformation/kuali_jenkins
     ```
  
     *NOTE: (There is an example of specifying a different s3 location below)*
  
  2. In this same bucket must exist application configuration files, like kc-config.xml for the research app, and environment variable files for docker containers to reference (contain database connection details and other app parameters).
  
- **[Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) Entry:**
  There should be a secret named "kuali/jenkins/administrator" accessible from the secrets manager service before stack creation begins.
  This secret should have a secret string:

  ```
  {
    "username": "admin",
    "password": "[PASSWORD]"
  }
  ```

  Alternatively, if this secret does not exist, then you must provide an "ADMIN_PASSWORD" stack parameter and the secret will be automatically created by the helper script *(see below)*.

### Steps:

Included is a bash helper script (main.sh) that serves to simplify many of the command line steps that would otherwise include a fair amount of manual entry. 

1. **Clone this repository**:

   ```
   git clone https://github.com/bu-ist/kuali-infrastructure.git
   cd kuali-infrastructure/kuali_jenkins
   ```

2. **Build docker image:**
   Many jenkins jobs use the [Active Choices Plugin](https://plugins.jenkins.io/uno-choice/) to add more dynamic behavior to fields in a job. Field values/choices can be dynamically populated based on selections/entries in other fields. The code to drive this dynamic behavior must be entered by the job author as groovy scripting in special text areas connected to the associated field(s). This can quickly become cumbersome and difficult to maintain the more involved the dynamic behavior becomes. To solve this, the logic behind the dynamic behavior is moved out into a docker container acts as a simple website that returns html for rendering in the job. The groovy scripting of each job field is reduced down to an http call to this container over localhost providing the its current value and all other field values. The returned html is used to re-render a single field (html fragment) or many fields at once.
   
2. **Create the stack:**
   Use the main.sh helper script to create the jenkins cloudformation stack.
   Examples:

   - Accept all defaults, but use the dryrun parameter to see the command to be issued without running it.

     ```
     sh main.sh create-stack dryrun=true
     ```

   - Create a jenkins server, giving it a size down from the default xlarge

     ```
     sh main.sh create-stack ec2_instance_type=m5.large
     ```

   - Specify a non-default s3 location for supporting templates and scripts:

     ```
     sh main.sh create-stack template_bucket_path=s3://mybucket/path/to/files
     ```

   - Part of preparing for stack creation is the automatic upload of bash scripts to s3 that get imported by the jenkins ec2 instance during its creation. This step can be skipped if no changes were made to any of these scripts. The following example skips the script upload and attempts to delete and recreate the prior stack with a larger instance size and a different name.

     ```
     sh main.sh recreate-stack \
       stack_name=kuali-jenkins2 \
       global_tag=kuali-jenkins2 \
       ec2_instance_type=m5.2xlarge \
       s3_refresh=false
     ```

     
