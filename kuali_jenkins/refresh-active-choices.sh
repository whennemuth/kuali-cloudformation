#!/bin/bash

# Build this maven project as a jar, save the jar in s3, and issue a command to the jenkins server to download that jar.
# All dependencies are saved inside the jar using the shade plugin.

source ../scripts/common-functions.sh

parseArgs $@

buildJar() {
  cd $MAVEN_PROJECT
  mvn package shade:shade
}

uploadJar() {
  aws s3 cp target/kuali-jenkins-ui.jar s3://kuali-conf/
  aws s3 cp $LOCAL_JAR $S3_JAR
}

getJenkinsInstanceId() {
  filters=(
    'Key=Function,Values='${kualiTags['Function']}
    'Key=Service,Values='${kualiTags['Service']}
    "Key=Name,Values=kuali-jenkins"
  )
  pickEC2InstanceId ${filters[@]} > /dev/null
  cat ec2-instance-id
  rm -f ec2-instance-id
}

downloadJar() {
    aws ssm send-command \
    --instance-ids $(getJenkinsInstanceId) \
    --document-name "AWS-RunShellScript" \
    --comment "Refesh Active Choices" \
    --parameters commands="aws s3 cp $S3_JAR $TARGET_JAR && \
        chown jenkins:jenkins $TARGET_JAR"
}

refresh() {
  
  buildJar

  uploadJar

  downloadJar
}

refresh

# # Set up an alias for this script as something like this:
# refreshjobs() {
#   local jarname=kuali-jenkins-ui.jar
#   local maven_project=/c/whennemuth/workspaces/jenkins_workspace/KualiUI
#   local local_jar=$maven_project/target/$jarname
#   local s3_jar=s3://kuali-conf/$jarname
#   local target_jar=/var/lib/jenkins/.groovy/lib/$jarname
#   cd /c/whennemuth/workspaces/ecs_workspace/cloud-formation/kuali/kuali_jenkins
#   sh refresh-active-choices.sh \
#     profile=infnprd \
#     maven_project=$maven_project \
#     local_jar=$local_jar \
#     s3_jar=$s3_jar \
#     target_jar=$target_jar
# }
