#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...
DRYRUN=true
DEBUG=false
# STACK='my-stack-name|stg|hitesh'
STACK='my-stack-name|stg|stg'
# STACK='my-stack-name|stg|chopped-liver'
BUILD_TYPE=pre-release
GIT_REF=changes_log4j
GIT_REF_TYPE=branch
GIT_COMMIT_ID=029b7611e44a0ba4805e749a6c2372990a8f8a0b
ECR_REGISTRY_URL=770203350335.dkr.ecr.us-east-1.amazonaws.com
AWS_PROFILE=infnprd
LEGACY_DEPLOY='stg'
LEGACY_LANDSCAPE='stg'

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research.sh