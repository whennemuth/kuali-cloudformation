#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...
DRYRUN=true
DEBUG=false
# STACK='my stack name|qa|qa'
STACK='my stack name|stg|chopped-liver'
GIT_REF=mybranch
GIT_REF_TYPE=branch
GIT_COMMIT_ID=a2caa81630c2763dd1c30cd7d43ce51923171f52
ECR_REGISTRY_URL=770203350335.dkr.ecr.us-east-1.amazonaws.com

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research.sh