#!/bin/bash

checkAwsProfile() {
  [ -n "$AWS_PROFILE" ] && return 0
  while true ; do
    printf "Enter the AWS_PROFILE\n: "
    read AWS_PROFILE
    [ -z "$AWS_PROFILE" ] && echo "EMPTY VALUE! Try again" && continue;
    break;
  done
  export AWS_PROFILE=$AWS_PROFILE
}

checkTestHarness() {
  if [ -n "$JENKINS_HOME" ] ; then
    echo "Not a local environment - assuming jenkins server..."
  else
    echo "Simulating jenkins environment..."
    parseArgs $@
    if [ -z "$JENKINS_HOME" ] ; then
      JENKINS_HOME=$(dirname "$(pwd)")
    fi
    if [ -z "$DRYRUN" ] ; then
      DRYRUN='true'
    fi
    if [ -z "$PARAMETERS" ] ; then
      if [ -n "$PARAMETERS_FILE" ] ; then
        source "$PARAMETERS_FILE"
      else
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
      fi
    fi
  fi

  checkAwsProfile
}

source $(pwd)/kuali_jenkins/job-scripts/main.sh