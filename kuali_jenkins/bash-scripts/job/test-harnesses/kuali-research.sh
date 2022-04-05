#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...
DRYRUN=true
DEBUG=false
STACK='my-stack-name|stg|hitesh'
# STACK='my-stack-name|stg|stg'
# STACK='my-stack-name|stg|chopped-liver'
BUILD_TYPE=feature
GIT_REF=bu-master
GIT_REF_TYPE=branch
GIT_COMMIT_ID=56bac9d4c4767e7336caee1b0a253662ae333ef4
ECR_REGISTRY_URL=770203350335.dkr.ecr.us-east-1.amazonaws.com
AWS_PROFILE=infnprd
LEGACY_DEPLOY='stg'
LEGACY_LANDSCAPE='stg'
JENKINS_HOME=$(dirname $(pwd))
ADVANCED="$(cat <<EOF
  myvar1=apples
  myvar2=oranges
  myvar3=pears
  # WAR_FILE=feature
  WAR_FILE=$(pwd)/$(mktemp tempwar-XXXXXXXXXX-coeus-webapp-2001.0040.war)
EOF
)"

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research.sh

rm -f "$WAR_FILE" 2> /dev/null