## AWS Elasticsearch Implementation for Kuali Research

### Overview

Excerpt from [Kuali Zendesk docs](https://kuali-research.zendesk.com/hc/en-us/articles/360029976374-Dashboard-Search-Records):

> *The search option in the Dashboard menu is omni search functionality that allows you to search across all sponsored modules (Proposal, IP, Award, Negotiations, Subaward) by a single criteria and by a subset of criteria.  This allows additional flexibility for search needs beyond the existing lookups (i.e. Proposal, Award, etc.) that are limited to the given module.  This search is only available if utilizing the new Dashboard in Kuali Research.* 

The search option in the dashboard menu is powered by Elasticsearch:

> *Elasticsearch is an open-source, RESTful, distributed search and analytics engine built on Apache Lucene. Since its release in 2010, Elasticsearch has quickly become the most popular search engine, and is commonly used for log analytics, full-text search, security intelligence, business analytics, and operational intelligence use cases.* 



### Setup steps:

1. #### **Cloudformation**

   We are using the AWS elasticsearch service.
   This involves creating an elasticsearch cluster of managed ec2 instances running as nodes.
   The corresponding cloudformation template is currently located at:

   ```
   https://s3.amazonaws.com/kuali-conf/cloudformation/kuali_peripherals/es_for_kuali.yaml
   ```

   Among other parameters, there is a landscape parameter to designate which environment the cluster is being created for (sb, ci, qa, stg, prod). You can create the stack from the AWS management console, or you can run it from the command line (provided you have a sufficient IAM role). The examples below specify the landscape parameter and use defaults for the rest (like cluster & ec2 size, etc.)

   1. **Service linked role**

      Before running the cloudformation template, you must first ensure that there is a [service linked role]( https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html ) created. It does not appear possible to create this role as part of the stack by including a `AWS::IAM::ServiceLinkedRole` resource in the template doing so will cause the stack creation to roll back with an error stating:

      > "Before you can proceed, you must enable a service-linked role to give Amazon ES permissions to access your VPC."

      Therefore, you must ensure that this role exists:

      ```
      aws iam get-role --role-name AWSServiceRoleForAmazonElasticsearchService
      ```

      If this call indicates the role does not exist, create it with:

      ```
      aws iam create-service-linked-role --aws-service-name es.amazonaws.com
      ```

      This role has probably already been created in the kuali AWS account.

   2. **Cloudwatch logging resource policy**

      You must have already created a resource based policy that grants elasticsearch access to cloudwatch logging. NOTE: This is not a role - SEE [related documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_compare-resource-policies.html)

      Elasticsearch will attempt to log to the cloudwatch logsGroup set up for it if specified with the LogPublishingOptions  property:

      ```
        KualiElasticsearchDomain:
          Type: AWS::Elasticsearch::Domain
          Properties:
          ...
            LogPublishingOptions:
              'ES_APPLICATION_LOGS' :
                CloudWatchLogsLogGroupArn: !GetAtt KualiESLogsGroup.Arn
                Enabled: true
          ...
      ```

      There doesn't seem to be a way to doing this by giving the elasticsearch domain a role with the equivalent policy. With any of the LogPublishingOptions enabled without this resource policy, the stack create/update will fail with the following message:

      > "The Resource Access Policy specified for the CloudWatch Logs log group KualiElasticSearchLogsGroup does not grant sufficient permissions for Amazon Elasticsearch Service to create a log stream. Please check the Resource Access Policy."

      This resource poilicy is likely to have already been created.
      To check if this is the case use:

      ```
      aws logs describe-resource-policies
      ```

      You should see output from this command that outlines the policy with a policy-name of `Kuali-elasticsearch-logging-policy`. This policy will cover logging for any of the elasticsearch domains across environments (it is not environment specific).

      If the policy is not found, create it as follows:

      ```
        aws logs put-resource-policy \
          --policy-name Kuali-elasticsearch-logging-policy \
          --policy-document '{
          "Version": "2012-10-17", 
          "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Service": "es.amazonaws.com"
                },
                "Action": [
                  "logs:PutLogEvents",
                  "logs:CreateLogStream"
                ],
                "Resource": "arn:aws:logs:us-east-1:770203350335:log-group:/aws/aes/domains/kuali-elasticsearch*"
              }
            ]
          }'
      ```

      

   3. **Create the stack**

      ```
      bucket=s3.amazonaws.com/kuali-conf
      yaml=cloudformation/kuali_peripherals/es_for_kuali.yaml
      environment=sb
      
      aws cloudformation create-stack \
        --stack-name stackname=kuali-elasticsearch-$environment \
        --template-url $bucket/$yaml \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameters 'ParameterKey=Landscape,ParameterValue='$environment
      ```

      an update to the creation of the above stack would be:

      ```
      aws cloudformation update-stack \
        --stack-name stackname=kuali-elasticsearch-$environment \
        --template-url $bucket/$yaml \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameters 'ParameterKey=Landscape,ParameterValue='$environment \
        --no-use-previous-template
      ```

      The stack creation will take between 15 and 20 minutes.
      

2. #### **Configuration**

   ------

   Once the stack creation has finished, one of the outputs will be "DomainEndpoint", ie:

   ```
   vpc-kuali-elasticsearch-stg-2xrjutf3dfljvt4s5yrikjiuk4.us-east-1.es.amazonaws.com
   ```

   For  better security, the elasticsearch domain is created within our existing kuali AWS VPC, using existing subnets. SEE: [VPC Support for Amazon Elasticsearch Service Domains](https://docs.aws.amazon.com/elasticsearch-service/latest/developerguide/es-vpc.html) 

   Both the KC monolith and dashboard applications need to be configured with this domain endpoint:
   

   1. **kc-config.xml**

      Add the following to kc-config.xml

      *(NOTE: prepend "https:// to domainEndpoint output value and set it to the elasticsearch.hosts value. The value below is just an example )*

      ```
      <param name="elasticsearch.enabled">true</param>
      <param name="elasticsearch.hosts">https://vpc-kuali-elasticsearch-sb-db24x4yzmvesxlcsw5mrcym2py.us-east-1.es.amazonaws.com</param>
      <param name="elasticsearch.index.name">documents</param>
      ```

      Restart the kuali-research docker container(s).
   
2. **Parameter Lookup**
  
   Navigate to the parameter screen in the dashboard frontend:
   
   `All Links > System Administration > Parameter`
   
   Search for `*elasticsearch*`
   
   Set each result as follows:
   
   - **Elasticsearch_Index_Job_Cron_Expression**: The cron expression to determine the schedule of the Elasticsearch document indexing job. Default is nightly at midnight (0 0 0 * * ?)." 
        *(Arbitrarily leaving at midnight for now)*
   
   - **Elasticsearch_Index_Job_Enabled**: Determines if the Elasticsearch document indexing job is enabled. Default is false.
        *(Set to True)*
   
   - **Elasticsearch_Index_Job_Skip_Misfire:**  In the event that the Elasticsearch document indexing failed to run at its scheduled time (due to KC being offline, for instance), determines whether the job should run right away (false) or wait until the next scheduled run(true). Default is false. 
        *(Set to True. This means that the cron schedule is observed even if the last run encountered error.)*
   
   - **Elasticsearch_Index_Skip_Default_And_Unit_Roles:**  Whether or not to skip indexing individual role memberships for default and unit-qualified roles, instead using unit memberships for Dashboard access control. Default is false.
        *(Set to False. Setting to true tightens restrictions on which items in the search results you are allowed to see. It's not fully understood yet how exactly how this parameter operates.)*
   
     *<u>**IMPORTANT!**</u>*
        *IF YOU HAVE ALREADY INDEXED THE ELASTICSEARCH CLUSTER AND YOU SWITCH THIS SETTING, YOU WILL NEED TO REINDEX THE ENTIRE CLUSTER AGAIN. This is because each indexed document maintains a "viewers" list of who is authorized to see it as a search result, and resetting this parameter will change that list*
   
3. **Dashboard Environment variables**
  
   The docker container running the dashboard application will need to be restarted, having added the following environment variables (Again, the first value is just an example value):
   
   - `ELASTICSEARCH_URL=https://vpc-kuali-elasticsearch-sb-db24x4yzmvesxlcsw5mrcym2py.us-east-1.es.amazonaws.com`
   - `ELASTICSEARCH_INDEX_NAME=documents`
   - `OMNISEARCH_ENABLED=true`
   - `USE_LEGACY_APIS=false`
   
   Remove the dashboard docker containers and re-run with these environment variables included.
   
   Currently all environment variables are stored in "environment.variables.s3.env" files in our kuali-conf bucket and are automatically downloaded as part of the jenkins job for running the dashboard app.
   
   Then when you navigate to the dashboard in the browser you should see the "Search" menu item to the left.
   
   However, if you click the down arrow for the "Search Everywhere" button, you will see no options.
      You will not be able to see any search results yet either.
      You must perform an initial indexing of the elasticsearch cluster first.
         

3. #### Index the cluster

   ------

   - **Initial indexing**

     The kc monolith exposes a web api endpoint to trigger an on-demand, one-time indexing of the entire cluster. Save the following off to a file "reindex.sh" and run with the following command:

     `sh reindex.sh [env]`, where env indicates the environment to run against (sb, ci, qa, stg, prod).

     Example: `sh reindex stg`

     ```
     getToken() {
       local username=${1:-'admin'}
       local password=${2:-'password'}
       local env="-$ENV"
       [ "$ENV" == "prod" ] && env=""
       
       local TOKEN=$(curl \
         -X POST \
         -H "Authorization: Basic $(echo -n "$username:$password" | base64 -w 0)" \
         -H "Content-Type: application/json" \
         "https://kuali-research${env}.bu.edu/api/v1/auth/authenticate" \
         | sed 's/token//g' \
         | sed "s/[{}\"':]//g" \
         | sed "s/[[:space:]]//g")
     
         echo $TOKEN
     }
     
     triggerElasticSearchIndexingJob() {
       local env="-$ENV"
       [ "$ENV" == "prod" ] && env=""
       local host="https://kuali-research${env}.bu.edu"
       local token=$(getToken)
     
       curl \
         -X POST \
         -H "Authorization: Bearer $token" \
         -H 'Content-Type: application/json' \
         "$host/kc/research-common/api/v1/index-documents"
     }
     
     ENV=${1,,}
     [ -z "$ENV" ] && echo "Missing environment parameter!" && return 1
     
     triggerElasticSearchIndexingJob
     ```

   - **Quartz job**

     With the `Elasticsearch_Index_Job_Enabled` parameter set to true, a java-based quartz job will run periodically to keep the indexing up to date. During the day, when documents are being created/edited, the index should be updated correspondingly to reflect the changes, so theoretically, the re-indexing is just a precaution to catch any indexing failures.

     The `Elasticsearch_Index_Job_Cron_Expression` parameter will govern when this quartz job is triggered.