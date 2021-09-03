#!/bin/bash

source /var/lib/jenkins/_cfn-scripts/utils.sh

startJenkins

# turnOffSecurity

getCLI

# # Download any .jpi file available directly from s3:
# aws s3 cp s3://${TemplateBucketName}/cloudformation/kuali_jenkins/plugin-files/dynamicparameter.jpi plugins/
# chown jenkins:jenkins 

# Download the rest from the download center:
for plugin in $(cat plugin-list | sed 's/\ \+//g') ; do
  if [ "${plugin:0:1}" != '#' ] ; then
    java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 install-plugin $plugin
  fi
done

chown -R jenkins:jenkins $JENKINS_HOME

restartJenkins

printf "\n\n"
