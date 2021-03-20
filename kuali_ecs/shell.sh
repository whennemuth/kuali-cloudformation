#!/bin/bash

# Use this script to start an ssm shell session with the first locatable ec2 instance that is part of 
# an ecs cluster identified by landscape.
# Example: sh shell.sh mylandscape

getCluster() {
  local landscape="$1"
  aws ecs list-clusters \
    --output text 2> /dev/null \
    | grep 'kuali' \
    | grep '\-'$landscape'\-' \
    | awk '{print $2}'
}

getFirstContainerInstance() {
  local clusterArn="$1"
  aws ecs list-container-instances \
    --cluster $clusterArn \
    --output text \
    --query 'containerInstanceArns[]' 2> /dev/null \
    | awk 'BEGIN{RS="[[:space:]]+"} {print $1}' \
    | head -1
}

getInstanceId() {
  local clusterArn="$1"
  local containerInstanceArn="$2"
  aws ecs describe-container-instances \
    --cluster $clusterArn \
    --container-instances $containerInstanceArn \
    --output text \
    --query 'containerInstances[].{ec2InstanceId:ec2InstanceId}' 2> /dev/null
}

windows() {
  [ -n "$(ls /c/ 2> /dev/null)" ] && true || false
}

startShell() {
  local landscape=$1
  [ -z "$landscape" ] && echo "Missing landscape!" && exit 1
  
  local clusterArn=$(getCluster $landscape)
  local containerInstanceArn=$(getFirstContainerInstance $clusterArn)
  local instanceId=$(getInstanceId $clusterArn $containerInstanceArn)

  local cmd="aws ssm start-session --target $instanceId"
  if windows ; then
    cmd="winpty $cmd"
  fi

  eval "$cmd"
}

startShell $@