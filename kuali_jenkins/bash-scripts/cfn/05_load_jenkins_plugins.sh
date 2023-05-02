#!/bin/bash

dos2unix /var/lib/jenkins/_cfn-scripts/utils.sh
source /var/lib/jenkins/_cfn-scripts/utils.sh

TEMPLATE_BUCKET=${TEMPLATE_BUCKET:-"kuali-conf"}

# Install specific versions of plugins from jpi files stored in s3 bucket.
# (NOTE: Alternatively, most plugin jpi files will be available from here: https://updates.jenkins.io/download/plugins/)
installPluginsFromS3Bucket() {
  local plugins=$JENKINS_HOME/plugins
  [ ! -d $plugins ] && mkdir -p $plugins
  cd $plugins
  aws s3 sync s3://$TEMPLATE_BUCKET/cloudformation/kuali_jenkins/plugin-files/jenkins-2.322-1.1/ . --exclude "*" --include "*.jpi"
  chown -R jenkins:jenkins $JENKINS_HOME
  startJenkins
  getCLI
  printf "\n\n"
}

# Get the latest version of all plugins listed in the specified file from the jenkins download center, using the jenkins cli.
installLatestPluginsFromList() {  
  startJenkins
  # turnOffSecurity
  getCLI

  local list=${1:-'/var/lib/jenkins/plugin-list'}
  for plugin in $(cat $list | sed 's/\ \+//g') ; do
    if [ "${plugin:0:1}" != '#' ] ; then
      java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 install-plugin $plugin
    fi
  done
  chown -R jenkins:jenkins $JENKINS_HOME
  restartJenkins
  printf "\n\n"
}

pluginsAvailableInS3() {
  local alternate="s3://$TEMPLATE_BUCKET/cloudformation/kuali_jenkins/plugin-files/${JENKINS_VERSION}/"
  local s3dir=${JENKINS_PLUGINS_S3_LOCATION:-$alternate}
  local pluginCount=$(aws s3 ls $s3dir | wc -l)
  [ $pluginCount -gt 0 ] && true || false
}

if pluginsAvailableInS3 ; then
  installPluginsFromS3Bucket
else
  installLatestPluginsFromList
fi

