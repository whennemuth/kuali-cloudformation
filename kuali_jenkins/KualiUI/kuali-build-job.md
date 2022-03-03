

## Kuali build Jenkins job

<img align="left" src="C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\kuali_jenkins\jenkins1.png" alt="jenkins1" style="margin-right:15px;" />The jenkins job that builds and deploys kuali research to a selected environment exists on a
ec2-based jenkins host in the CSS (Common security services) aws account.
**Job features:**
   -- Full java/maven build
   -- Creation and uploading of docker image to registry
   -- Deployment/Redeployment of docker image to target application server(s).
   -- Cross-account synchronization of new docker images between registries CSS and "legacy".
   -- Cross-account deployment to target application server(s) in "legacy" account.



### Terms:

- **"CSS"**: Common security services. Refers to 2 aws accounts, production and non-production that provide an for standardized networking and security infrastructure where BU applications can be deployed. Most php applications, and now kuali-research are deployed there.
- **"Legacy"**: This refers to the aws account where kuali research was first deployed to get it off-prem (mostly) and into the cloud.
  We are migrating kuali research from here to the CSS account.

### Directions:

1. #### **Get Jenkins server address:**

   The jenkins server in the CSS account is not associated with any DNS name and must be reached using its IP address.
   Combined with the fact that it is re-creatable through cloud-formation, it's address may change from time to time.
   There are several ways to determine what the jenkins ip address is.

   1. **Email:**
      Check your email history. If you are working with this server, you probably have been sent the most recent url for jenkins.

   2. **EC2 dashboard:** 
      It will be listed in the ec2 dashboard. Login into the non-production CSS account *(770203350335)*. Login and navigate [here](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:v=3;search=:jenkins).
      Look for *"Private IPv4 addresses*" under the details tab.

   3. **Cloudformation dashboard:**
      You can find the jenkins server url listed as an output of the cloudformation stack associated with its creation. 
      Login to the non-production CSS account *(770203350335)* and navigate [here](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks?filteringStatus=active&filteringText=jenkins&viewNested=true&hideStacks=false&stackId=)
      This link will take you to the "Outputs" tab where the entire url is under output "JenkinsPrivateUrl"

   4. **AWS CLI:**
      The jenkins ec2 instance can be looked up by tags, which will always be the same. You can use the aws cli for this.

      ```
      aws ec2 describe-instances --instance-id \
          $(aws resourcegroupstaggingapi get-resources \
            --resource-type-filters ec2:instance \
            --tag-filters 'Key=Function,Values=kuali' 'Key=ShortName,Values=jenkins' \
            --query 'ResourceTagMappingList[].{ARN:ResourceARN}' \
            --output text | cut -d'/' -f2 | sed 's/\n//g') \
       --output text \
       --query 'Reservations[0].Instances[0].{ip:PrivateIpAddress}'
      ```

   Once you have the ip address, plug it in as follows to go directly to the kuali build job:

   ```
   [private jenkins ip]:8080/view/Kuali-Research/job/kuali-research/build?delay=0sec.
   ```

2. More to come...

