#!/bin/bash

# -------------------------------------------------------------------------------------------------------------------
# Once a target group becomes unhealthy, the ec2 instance will be deregistered and become terminated before too long.
# If before that time, any logs that are not being streamed to cloudwatch are not saved, they will be lost.
# This script gathers all logs related to ecs and uploads them to a bucket if the instance is marked unhealthy.
# This check is performed every 15 minutes, which is sufficient time before termination occurs.
# -------------------------------------------------------------------------------------------------------------------

REGION="${REGION:-$1}"
BUCKET="${BUCKET:-$2}"
LANDSCAPE="${LANDSCAPE:-$3}"

if [ -z "$REGION" ] ; then
  echo "Required parameter missing: REGION - cancelling script!"
  exit
fi
if [ -z "$BUCKET" ] ; then
  echo "Required parameter missing: BUCKET - cancelling script!"
  exit
fi

export AWS_DEFAULT_REGION="$REGION"

getThisInstanceId() {
  curl -s http://169.254.169.254/latest/meta-data/instance-id
}

getKcTargetGroupArn() {
  aws \
    elbv2 describe-target-groups \
    --query 'TargetGroups[?HealthCheckPath==`/kc/healthCheck/`]' \
    | jq -r '.[0].TargetGroupArn'
}

getThisInstanceHealth() {
  local instanceId="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
  aws \
    elbv2 describe-target-health \
    --target-group-arn "$(getKcTargetGroupArn)" \
    --query 'TargetHealthDescriptions[?Target.Id==`'$(getThisInstanceId)'`]' \
    | jq -r '.[0].TargetHealth.State'
}

thisInstanceIsUnhealthy() {
  [ "$(getThisInstanceHealth)" == 'unhealthy' ] && true || false
}

collectECSLogs() {
  # Download the log collector script
  if [ ! -f ecs-logs-collector.sh ] ; then
    curl -O https://raw.githubusercontent.com/awslabs/ecs-logs-collector/master/ecs-logs-collector.sh
  fi
  
  # Clear prior script output
  rm -rf collector
  rm -f collect-i-*.tgz

  # Run the script
  bash ./ecs-logs-collector.sh
}

uploadECSLogs() {
  local fn="$(ls -1 collect-i-*.tgz | head -1)"
  local cmd="aws s3 cp "$fn" "s3://$BUCKET/ecs-logs-collector/target-group-targets/kc/unhealthy/$(getThisInstanceId)/${LANDSCAPE}-${fn}""
  echo "$cmd"
  eval "$cmd"
}

checkWorkDir() {
  workdir='/tmp/ecs_logs_collector'
  if [ ! -d $workdir ] ; then
    mkdir $workdir
  fi
  cd $workdir
}

if thisInstanceIsUnhealthy ; then

  echo "$(date +%F-%T): Unhealthy status detected!"

  checkWorkDir

  collectECSLogs

  uploadECSLogs

else
  echo "$(date +%F-%T): Healthy status"
fi