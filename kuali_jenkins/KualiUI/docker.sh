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

defaultDockerhubUser='wrh1'
dockerhubPswd=${PASSWORD}
dockerhubUser=${USER:-"$([ -n "$PASSWORD" ] && echo $defaultDockerhubUser)"}
imageShortName='kuali-jenkins-http-server'
region="${REGION:-${AWS_REGION:-"us-east-1"}}"

build() {
  for i in $(docker images -a -q --filter dangling=true) ; do
    docker rmi $i
  done
  docker build -t $imageShortName .
}

stop() {
  docker stop active-choices-server 2> /dev/null
}

push() {
  local image=$imageShortName
  if [ -n "$dockerhubPswd" ] ; then
    local user=${dockerhubUser}
    # registry will default to dockerhub
    local repo=${REPO:-$dockerhubUser}
    if [ -z "$dockerhubPswd" ] ; then
      printf "Enter your dockerhub login password: "
      read pswd
    else
      local pswd=$dockerhubPswd
    fi
    [ -z "$dockerhubUser" ] && dockerhubUser=$defaultDockerhubUser
  else
    if ! ecrRepoExists $image ; then
      exit 0
    fi
    local registry=$(getEcrRegistryName)
    local repo="$registry"
    local user="AWS"
    local pswd="$(aws ecr get-login-password --region $region)"
  fi

  echo $pswd | docker login -u $user --password-stdin $registry

  docker tag $image $repo/$image

  docker push $repo/$image
}

getEcrRegistryName() {
  echo "$(aws sts get-caller-identity --output text --query 'Account').dkr.ecr.$region.amazonaws.com"
}

ecrRepoExists() {
  local repo="$1"
  local exists="$(
    aws ecr describe-repositories \
      --output text \
      --query 'repositories[?repositoryName==`'$repo'`].{arn:repositoryName}'
  )"
  echo "$exists"
  if [ "$exists" == "$repo" ] ; then
    echo "\"$repo\" found in elastic container registry..."
  else
    echo "\"$repo\" not found in elastic container registry, select action:"
    select choice in \
      'Create the repository '$repo \
      'Cancel' ; do 
        case $REPLY in
          1) 
            aws ecr create-repository \
              --repository-name $repo \
              --tags \
                Key=Function,Value=${kualiTags['Function']} \
                Key=Service,Value=${kualiTags['Service']}
            if [ $? -eq 0 ] ; then
              exists="$repo"
            else
              echo "Encountered error creating $repo! Cancelling..."
              exists=""
            fi
            break ;;
          2) 
            exists=""
            break ;;
          *) echo "Valid selections are 1 or 2"
        esac
    done;
  fi
  [ -n "$exists" ] && true || false
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
    $imageShortName \
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
  if [ -n "$dockerhubPswd" ] ; then
    local kualiUIImage=$dockerhubUser/$imageShortName
  else
    local kualiUIImage=$(getEcrRegistryName)/$imageShortName
  fi

  local S3Script='s3://kuali-conf/cloudformation/kuali_jenkins/scripts/jenkins-docker.sh'

  aws s3 cp ../bash-scripts/jenkins-docker.sh $S3Script 
  
  export AWS_PAGER=""

  cmd="aws s3 cp $S3Script /etc/init.d/jenkins-docker.sh"
  cmd="$cmd refresh"
  cmd="$cmd kuali_ui_image=$kualiUIImage"
  cmd="$cmd log_level=$loggingLevel"
  cmd="$cmd 2>&1 > /tmp/jenkins-docker-refresh.log"

  aws ssm send-command \
    --instance-ids $(getJenkinsInstanceId) \
    --document-name "AWS-RunShellScript" \
    --comment "Update and run active choices docker refresh script" \
    --no-paginate \
    --parameters commands="$cmd"
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
    push ;;
  deploy)
    jenkinsPull $@ ;;
  all)
    build
    push
    jenkinsPull
    ;;
esac

# Example for dockerhub: 
# sh docker.sh all user=wrh1 password=[wrh1 password] logging_level=TRACE
#
# Example for ECR:
# sh docker.sh all profile=[your profile] logging_level=DEBUG

