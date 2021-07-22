#!/bin/bash

##############################################################################################
# Some jenkins jobs have active choices parameters fields that get their html content from http
# calls to a docker container running on the jenkins host. That container is running with this
# java maven application, including a simple Http handler.
# In order to get a docker container running on the jenkins host, use this script to:
#  1) Build the docker image
#  2) Push the docker image up to a docker registry
#  3) Issue a command to the jenkins host to flush any existing containers, delete the existing
#     image, and run the containers again (which will pull the new image from the registry)
##############################################################################################

source ../../scripts/common-functions.sh

parseArgs $@

build() {
  for i in $(docker images -a -q --filter dangling=true) ; do
    docker rmi $i
  done
  docker build -t kuali-jenkins-http-server .
}

stop() {
  docker stop active-choices-server 2> /dev/null
}

push() {
  local user=${1:-'wrh1'}
  local repo=${2:-'wrh1'}

  if [ -n "$PASSWORD" ] ; then
    # docker login -u $user -p $PASSWORD
    echo "$PASSWORD" | docker login -u $user --password-stdin
  else
    printf "Enter your docker login password: "
    read pswd
    echo $pswd | docker login -u $user --password-stdin
  fi
  docker tag kuali-jenkins-http-server $repo/kuali-jenkins-http-server
  docker push $repo/kuali-jenkins-http-server
}

run() {
  stop
  docker run \
    -d -t \
    --restart-unless-stopped \
    --rm \
    --name active-choices-server \
    -p 8001:8001 \
    -v //c/Users/wrh/.aws:/root/.aws \
    kuali-jenkins-http-server \
    $@
}

getJenkinsInstanceId() {
  filters=(
    'Key=Function,Values='${kualiTags['Function']}
    'Key=Service,Values='${kualiTags['Service']}
    "Key=Name,Values=kuali-jenkins"
  )
  pickEC2InstanceId ${filters[@]} > /dev/null
  cat ec2-instance-id
  rm -f ec2-instance-id
}

jenkinsPull() {
  local loggingLevel=${LOGGING_LEVEL:-'INFO'}
  aws ssm send-command \
    --instance-ids $(getJenkinsInstanceId) \
    --document-name "AWS-RunShellScript" \
    --comment "Refesh Active Choices" \
    --parameters commands="sh /etc/init.d/jenkins-docker.sh refresh $loggingLevel > /tmp/jenkins-docker-refresh.log"
}

task="$1"

shift

case "$task" in
  build)
    build ;;
  run)
    run $@ ;;
  stop)
    stop ;;
  push)
    push $@ ;;
  deploy)
    jenkinsPull $@ ;;
  all)
    build
    push
    jenkinsPull
    ;;
esac

# Example: 
# export AWS_PROFILE=[profile]
# sh docker.sh all password=[dockerhub password] logging_level=TRACE