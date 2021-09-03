#!/bin/bash

killContainers() {
  echo "Removing containers..."
  for c in $(docker ps -a --format='{{.ID}}|{{.Image}}') ; do
    local id=$(echo "$c" | cut -d'|' -f1)
    local image=$(echo "$c" | cut -d'|' -f2)
    if [ $image == $KUALI_UI_IMAGE ] ; then
      echo "Removing container: $id ..."
      docker rm -f $id
    fi
  done
}

killImage() {
  echo "Removing image $KUALI_UI_IMAGE ..."
  docker rmi $KUALI_UI_IMAGE
  echo "Removing dangling images..."
  for i in $(docker images -a -q --filter dangling=true) ; do
    docker rmi $i
  done
}

runJobContainer() {
  local jobClass=${JOB_CLASS:-'KUALI_STACK_CONTROLLER'}
  local port=${PORT:-'8001'}

  echo "Running job container..."
  docker run \
    -d \
    --restart unless-stopped \
    --name $jobClass \
    -p $port:$port \
    -v /var/lib/jenkins/.ssh:/root/.ssh \
    -e logging_level=${LOG_LEVEL:-'INFO'} \
    $KUALI_UI_IMAGE \
    job-class=$jobClass \
    ajax-host=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2> /dev/null)
}

runParametersContainer() {
  echo "Running parameter container..."
  local port=${PORT:-'8002'}
  docker run \
    -d \
    --restart unless-stopped \
    --name ${CONTAINER_NAME:-'KUALI_PARAMETER_CONTROLLER'} \
    -p $port:$port \
    -v /var/lib/jenkins/.ssh:/root/.ssh \
    -e logging_level=${LOG_LEVEL:-'INFO'} \
    $KUALI_UI_IMAGE
}

runContainers() {
  echo "Running containers..."

  if isEcrImage ; then
    loginToECR
  else
    echo "Registry is assumed to be a public dockerhub member."
  fi

  runJobContainer

  runParametersContainer
}

isEcrImage() {
  [ -n "$(echo $KUALI_UI_IMAGE | grep 'dkr.ecr')" ] && true || false
}

loginToECR() {
  local registry="$(echo $KUALI_UI_IMAGE | awk 'BEGIN {RS="/"} {print $1}' | head -1)"
  local image="$(echo $KUALI_UI_IMAGE | awk 'BEGIN {RS="/"} {print $1}' | tail -1)"
  local region="$(echo $registry | cut -d'.' -f4)"
  echo "Logging into ecr: $registry, in region: $region, to retrieve image: $image"
  local pswd="$(aws ecr get-login-password --region $region)"
  echo $pswd | docker login -u 'AWS' --password-stdin $registry
}

# Turn key=value pairs, each passed as an individual commandline parameter 
# to this script, into variables with corresponding values assigned.
parseArgs() {
  for nv in $@ ; do
    [ -z "$(grep '=' <<< $nv)" ] && continue;
    name="$(echo $nv | cut -d'=' -f1)"
    value="$(echo $nv | cut -d'=' -f2-)"
    echo "${name^^}=$value"
    eval "${name^^}=$value" 2> /dev/null || true
  done
}

task="${1,,}"

parseArgs $@ 2>&1

case "$task" in
  start)
    runContainers 2>&1
    ;;
  refresh)
    killContainers 2>&1
    killImage 2>&1
    runContainers 2>&1
    ;;
  *)
    runContainers 2>&1
    ;;
esac
