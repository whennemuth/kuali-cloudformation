#!/bin/bash

DUMMY_PARAMETERS='true'

# Use some random dummy entries for testing...
DRYRUN=false
DEBUG=false
AWS_PROFILE=infnprd
SOURCE_IMAGE='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-feature:2001.0040'
TARGET_IMAGE='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus:2001.0040'

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/kuali-research-promote-image.sh