## Automated shutdown and startup for AWS resources

Many resources like ec2 and RDS instances will not be needed at certain time during the day and week.
Such resources nonetheless continue to use up compute time during these times with the corresponding charges.
Knowing what these time frames are, it makes sense to shutdown the resources when they begin and to start them back up when they end.
This stack creates a single cloudwatch event that triggers at regular intervals a lambda function that checks for any and all resource that are tagged in such a way as to indicate a schedule for startup and shutdown.
Once having gathered the list of resources, the lambda will analyze the schedule of each and perform any startup/shutdown action if necessary.

### Local running/debugging:

These instructions are for testing lambda code written in nodejs locally.

**Requirements:**

- [Visual Studio Code](https://code.visualstudio.com/download)
- [Node.js runtime](https://nodejs.org/en/download/)
- [Npm](https://www.npmjs.com/get-npm) *(Note: you get this automatically with the Nodejs installation)*
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out by the nodejs code for the lambda function (disabling logging on [ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html) and [WAF](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html)). Preferably your user will have an admin role and all policies will be covered.
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)

**Steps:**

1. **Clone this repository**

   ```
   git clone https://github.com/bu-ist/kuali-infrastructure.git
   ```

2. **Create a launch configuration**
   To debug the lambda code as a local nodejs app, create a new or extend the existing .vscode launch.json file.
   There are 3 configurations below:

   1. **Mocked**: 

      The launch configuration starts in a "local_mocked" DEBUG_MODE that imports a mocked aws sdk that returns fake s3 bucket listings, bucket object listings, and bucket deletion results. A mock cloud-formation response object is also used.

   2. **Unmocked**:

      The launch configuration starts in a "local_unmocked" DEBUG_MODE that imports the actual aws sdk, which means that the s3 bucket should exist in whatever cloud account your profile indicates.

   3. **Pack**:
      Packs the application and zips the result. The zip file is ready for uploading to s3 in a location that the lambda function is configured to import it from. SEE the "Package the code for lambda" below for more details.

