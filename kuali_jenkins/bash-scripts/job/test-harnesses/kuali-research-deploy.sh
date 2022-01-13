#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...

# DRYRUN will not omit the send command, but a harmless command will be sent to the ec2 (write out a file with the date)
DRYRUN='true'
# DEBUG will cause set -x to be invoked
DEBUG='false'
STACK_NAME='kuali-ec2-warren'
LANDSCAPE='warren'
BASELINE='stg'
ECR_REGISTRY_URL='770203350335.dkr.ecr.us-east-1.amazonaws.com'
REGISTRY_REPO_NAME='kuali-coeus'
POM_VERSION='2001.0040'
NEW_RELIC_LOGGING='false'
NEW_RELIC_LICENSE_KEY='dummy_value'
NEW_RELIC_INFRASTRUCTURE_ENABLED='true'
LOGJ2_CATALINA_LEVEL='INFO'
LOGJ2_LOCALHOST_LEVEL='INFO'

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research-deploy.sh

if [ -d kuali-research-docker ] ; then
  rm -rf kuali-research-docker
fi