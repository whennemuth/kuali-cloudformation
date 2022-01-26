#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...
DRYRUN=true
DEBUG=false
AWS_PROFILE='infnprd'
JENKINS_WAR_FILE='/var/lib/jenkins/backup/kuali-research/war/feature/coeus-webapp-2001.0040.war'
POM_VERSION='2001.0040'
# REGISTRY_REPO_NAME='kuali-coeus'
REGISTRY_REPO_NAME='kuali-coeus-feature'
ECR_REGISTRY_URL='770203350335.dkr.ecr.us-east-1.amazonaws.com'
DOCKER_BUILD_CONTEXT_GIT_BRANCH='master'
JAVA_VERSION='11'
TOMCAT_VERSION='9.0.41'

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research-build-image.sh