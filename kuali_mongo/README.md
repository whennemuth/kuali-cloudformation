## Mongo Database

For the 5 standard environments (sandbox, ci, qa, staging, production), there are 5 corresponding databases hosted on the atlas mongodb service.
If you are creating an AWS stack for kuali-research and you specify one of these environments, the resulting service modules that require mongo database access will connect to these pre-existing mongo databases.

However, stack creation is not limited to specifying an environment name from only these 5 choices.
You can make up your own environment name and decide from there where the backend datasources should be.
So, this means 3 scenarios:

1. You've chosen one of the 5 standard environments and opt for the corresponding atlas mongodb database that already exists.
2. You've chosen a random environment name, but want to "point it at" one of the standard atlas mongodb databases that already exist.
3. You've chosen a random environment name and want modules that use mongo data to get it from a brand new mongo data source.

This cloudformation stack concerns itself with the 3rd option above.
A single ec2 instance is created with...

- Mongo server installed and waiting for connections
- The appropriate population of the cor-main module mongo data for proper configuration of shibboleth endpoints and default users.

### Prerequisites:

- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **AWS Session Manager Plugin**
  This plugin allows the AWS cli to launch Session Manager sessions with your local SSH client. The Version should be should be at least 1.1.26.0.
  Install instructions: [Install the Session Manager Plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)

### Steps:

1. **Run the stack**This is a nested stack and will be invoked by a parent stack, [ecs main stack](../kuali_ecs/README.md) for example.
   When running the main.sh script, you would simply include the parameter "CREATE_MONGO=true".
   However, you can run this separately:
   
   ```
   cd kuali_mongo
   sh main.sh create-stack \
     stack_name=kuali-mongo \
     global_tag=kuali-mongo \
     landscape=ci \
     private_subnet1=subnet-0d4acd358fba71d20 \
     app_security_group_id=sg-0b7dfc687aa869f39
   ```
   
   or a direct cloudformation call:
   
   ```
   aws \
       cloudformation update-stack \
       --stack-name kuali-mongo-ci \
       --no-use-previous-template \
       \
       --template-url https://s3.amazonaws.com/kuali-conf/cloudformation/kuali_mongo/mongo.yaml \
       --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
       --parameters '[
       {
       "ParameterKey" : "GlobalTag",
       "ParameterValue" : "kuali-mongo"
       }
       ,{
       "ParameterKey" : "Landscape",
       "ParameterValue" : "ci"
       }
       ,{
       "ParameterKey" : "VpcId",
       "ParameterValue" : "vpc-0290de1785982a52f"
       }
       ,{
       "ParameterKey" : "MongoSubnet",
       "ParameterValue" : "subnet-0d4acd358fba71d20"
       }
       ,{
       "ParameterKey" : "ApplicationSecurityGroupId",
       "ParameterValue" : "sg-0b7dfc687aa869f39"
       }
       ]'
   ```
   
2. **Check the content**
   You may want to check the content of the core mongo database to ensure it was correctly populated.
   For this we can tunnel into the mongo database ec2 instance on the mongo port (27017). This will make it seem as though the mongo database is running as localhost on your workstation. There is a separate tunnel.sh script for this:

   ```
   cd scripts
   sh tunnel.sh local_port=27017 remote_port=27017 landscape=ci
   ```

   This script utilizes [AWS System Manager Port Forwarding](https://aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/)
   *NOTE: You can set local_port to another port number (like 27018), in which case, just substitute that port number for 27017 everywhere you see it below.*
   You will first see some debug output and probably a report of having found a number of ec2 instances running in the specified environment:

   ```
   LOCAL_PORT=27017
   REMOTE_PORT=27017
   LANDSCAPE=ci
   Looking up InstanceId for kuali ec2 instance tagged with ci landscape...
   1) arn:aws:ec2:us-east-1:770203350335:instance/i-082f0f9b305922e8f  3) arn:aws:ec2:us-east-1:770203350335:instance/i-02cc2b48cd1ea549f
   2) arn:aws:ec2:us-east-1:770203350335:instance/i-0d13397402cd55cd0
   #?
   ```

   Select the choice by number of the arn that corresponds to the ec2 running mongo:

   ```
   #? 3
   Tunneling to i-02cc2b48cd1ea549f...
   
   Starting session with SessionId: wrh-07fd7946d5d486c20
   Port 27017 opened for sessionId wrh-07fd7946d5d486c20.
   ```

   The tunnel is now running.
   In a separate console window, run queries against localhost.
   Here are some examples for the cor-main mongo database:

   ```
   # List all the collections:
   mongo mongodb://localhost/core-development --quiet --eval 'db.runCommand( { listCollections: 1.0, nameOnly: true } )'
   
   # Print out all the content of the institutions and incommons collections:
   mongo mongodb://localhost:27017/core-development --quiet --eval 'db.getCollection("institutions").find({}).pretty()' && \
   printf "\n\n" && \
   mongo mongodb://localhost:27017/core-development --quiet --eval 'db.getCollection("incommons").find({}).pretty()'
   
   # Remove the institutions, incommons and users collections:
   mongo mongodb://localhost:27017/core-development --quiet --eval 'db.getCollection("incommons").drop({})' && \
   mongo mongodb://localhost:27017/core-development --quiet --eval 'db.getCollection("institutions").drop({})' && \
   mongo mongodb://localhost:27017/core-development --quiet --eval 'db.getCollection("users").drop({})'
   
   # Set the provider field of the kuali institution to "saml" (instead of "kuali") to invoke shibboleth authentication.
   mongo mongodb://localhost:27017/core-development --quiet \
     --eval 'db.getCollection("institutions")
       .updateOne(
         { "name":"Kuali" },
         { $set: { 
           "provider": "kuali"
         }
       })'
   ```
   
   To end the tunnel session, go back to the console it was created in and type "ctrl+c"
   On windows, this may not end the AWS port forwarding process, in which case, the next attempt to connect on the same port will result in:
   
   ```
   Cannot perform start session: listen tcp 127.0.0.1:27018: bind: Only one usage of each socket address (protocol/network address/port) is normally permitted.
   ```
   
   To remedy this, you must kill that process.
   
   ```
   # If using gitbash:
   export MSYS_NO_PATHCONV=1
   
   # List all processes listening on the mongo port
   $ netstat -a -b -o | grep -A 1 27017
     TCP    127.0.0.1:27017        IST-APP-WL-0120:0      LISTENING       22404
    [mongod.exe]
    
   # Kill the process
   $ taskkill /F /PID 22404
   SUCCESS: The process with PID 22404 has been terminated.
   
   ```
   
   

