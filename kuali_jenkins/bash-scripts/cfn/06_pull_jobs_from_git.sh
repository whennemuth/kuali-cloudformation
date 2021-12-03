#!/bin/bash

source /var/lib/jenkins/_cfn-scripts/utils.sh

pullJobs() {
  # Adjust file/directory permissions
  chmod 700 .ssh
  ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
  ssh-keyscan -t rsa github.com >> $JENKINS_HOME/.ssh/known_hosts

  # Configure github access
  [ ! -d jobs ] && mkdir jobs
  cd jobs
  [ ! -d .git ] && git init
  git config user.email "jenkins@bu.edu"
  git config user.name jenkins
  git remote add github git@github.com:bu-ist/kuali-research-jenkins.git

  # Pull all main/job configuration files from github
  eval `ssh-agent -s`
  ssh-add ../.ssh/bu_github_id_jenkins_rsa
  echo "Fetching from upstream and performing hard reset"
  git fetch github master
  git reset --hard FETCH_HEAD
  eval `ssh-agent -k`
}

# Having installed plugins from /var/lib/jenkins/plugin-list, newer plugin versions may have been installed.
# This is because the jenkins cli install-plugin function only installs the latest version, despite specifying major/minor designations.
# This function will replace all references in job config xml files for older versions of plugins to newer versions.
# This would happen automatically, but only after saving a job from the front end. Until that is done, plugins are essentially disabled
# until the job config file refers to the currently installed plugin version. 
updatePluginReferences() {
  local updated=()
  alreadyUpdated() {
    for member in ${updated[@]} ; do
      if [ "$member" == "$1" ] ; then
        local found='true'
        break;
      fi
    done
    [ -n "$found" ] && true || false
  }
  update() {
    local pluginName="$1"
    local configuredVersion="$2"
    local installedVersion=$(java -jar \
      $JENKINS_CLI_JAR $(getAdminUserCliParm) \
      -s http://localhost:8080 \
      list-plugins \
      | grep -E '^'$pluginName'\s' \
      | grep -oP '(\d\.?){2,}' \
      | head -1
    )
    if [ -z "$installedVersion" ] ; then
      echo "$pluginName@$configuredVersion plugin is referenced in job config file, but is not installed"
      return 0
    fi
    if [ "$configuredVersion" != "$installedVersion" ] ; then
      echo "Updating job config references to plugin $pluginName: $configuredVersion > $installedVersion"
      find . \
        -type f \
        -iname config.xml \
        -exec sed -i -E "s/plugin=\"${pluginName}@.*?\"/plugin=\"${pluginName}@${installedVersion}\"/g" {} \;
      updated=(${updated[@]} $pluginName)
    else
      echo "$pluginName@$installedVersion is current"
    fi
  }
  for plugin in $(grep -iroP 'plugin="[^"@]+@[\d\.]+"' . | cut -d':' -f2 | cut -d'"' -f2 | sort | uniq) ; do
    local name=$(echo $plugin | cut -d'@' -f1)
    if ! alreadyUpdated $name ; then
      local version=$(echo $plugin | cut -d'@' -f2)
      update $name $version
    fi
  done
}

pullJobs

updatePluginReferences

chown -R jenkins:jenkins $JENKINS_HOME

# restartJenkins

printf "\n\n"