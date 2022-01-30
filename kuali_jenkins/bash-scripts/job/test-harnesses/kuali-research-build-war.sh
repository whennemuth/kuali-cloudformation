#!/bin/bash

set -a

DUMMY_PARAMETERS='true'

fetch_scenario=${1:-"branch"}

# This test harness must be run from the root of the entire project
source $(pwd)/scripts/common-functions.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh


# Use some random dummy entries for testing...
DRYRUN=false
DEBUG=false
AWS_PROFILE='infnprd'
checkTestHarness # Will set the JENKINS_HOME value for debugging.
# JENKINS_HOME=${JENKINS_HOME:-"/c/whennemuth/workspaces/ecs_workspace/cloud-formation"}
# JENKINS_HOME=${JENKINS_HOME:-"/var/lib/jenkins"}
MAVEN_WORKSPACE="$JENKINS_HOME/latest-maven-build/kc"
BRANCH='feature'
# WARFILE_DIR=${MAVEN_WORKSPACE}/coeus-webapp/target
# BACKUP_DIR=$JENKINS_HOME/backup/kuali-research/war
# SCRIPT_DIR="$JENKINS_HOME/kuali-infrastructure/kuali_jenkins/bash-scripts/job"
# CHECK_DEPENDENCIES='true'
# GIT_REPO_URL='git@github.com:bu-ist/kuali-research.git'

fetchScenario() {
  case "$1" in
    branch)
      GIT_REF_TYPE='branch'
      GIT_REF='bu-master'
      GIT_COMMIT_ID='4ed034c3e2433ccb4a9d2672f09df024180cf748'
      ;;
    tag)
      GIT_REF_TYPE='tag'
      GIT_REF='coeus-2001.0040'
      GIT_COMMIT_ID='dc7490eb33ebe1c87ed582639e92a49cb88ee9d2'
      ;;
    commit)
      GIT_COMMIT_ID='4ed034c3e2433ccb4a9d2672f09df024180cf748'
      ;;
  esac
}

fetchScenario $fetch_scenario

sh -e $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research-build-war.sh