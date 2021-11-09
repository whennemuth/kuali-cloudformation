#!/bin/bash

# Use some random dummy entries for testing...
PARAMETERS=$(echo '
DEBUG=true&
STACK_ACTION=create&
STACK_TYPE=ecs&
AUTHENTICATION=shibboleth&
DNS=route53&
RDS_SOURCE=snapshot&
RDS_INSTANCES_BY_BASELINE=arn%3Aaws%3Ards%3Aus-east-1%3A770203350335%3Adb%3Akuali-oracle-ci&
RDS_SNAPSHOT=arn%3Aaws%3Ards%3Aus-east-1%3A770203350335%3Asnapshot%3Ards%3Akuali-oracle-ci-2021-04-04-22-08&
LANDSCAPE=qa&
WAF=true&
ALB=true&
MONGO=true&
ADVANCED=true&
ADVANCED_KEEP_LAMBDA_LOGS=true&
ADVANCED_MANUAL_ENTRIES=one%3D1%0Atwo%3D2%0Athree%3D3
' | tr -d '\n')

PARAMETERS=$(echo '
DRYRUN=true&
STACK_ACTION=create&
STACK_TYPE=ec2&
AUTHENTICATION=cor-main&
DNS=none&
RDS_SOURCE=shared-snapshot&
RDS_SNAPSHOT_SHARED=arn%3Aaws%3Ards%3Aus-east-1%3A730096353738%3Asnapshot%3Akuali-stg-10-27-2021&LANDSCAPE=dev&
WAF=false&
ALB=false&
MONGO=false&
ADVANCED=false
' | tr -d '\n')

# This test harness must be run from the root of the entire project 

source $(pwd)/kuali_jenkins/bash-scripts/job/test-harnesses/util.sh

source $(pwd)/kuali_jenkins/bash-scripts/job/main.sh