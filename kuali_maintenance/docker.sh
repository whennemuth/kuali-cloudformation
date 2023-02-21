#!/bin/bash

source ../scripts/common-functions.sh

parseArgs $@

region="${REGION:-${AWS_REGION:-"us-east-1"}}"
imageShortName="${IMAGE_NAME:-"kuali-maintenance"}"
imageTag="${IMAGE_TAG:-"latest"}"
htmlFile="${HTML_FILE:-"index.htm"}"
containerName='kuali-maint'

build() {
  stop 
  runCommand "docker build -t $(getImageName) --build-arg htmlfile=$htmlFile ."
  if isDryrun ; then
    echo "(dryrun) Removing dangling images..."
  else
    for i in $(docker images -a -q --filter dangling=true) ; do
      docker rmi $i
    done
  fi
}

run() {
  stop

  checkCerts

  runCommand "docker run \\
    -d \\
    --rm \\
    --name $containerName \\
    -e landscape="$LANDSCAPE" \\
    -e message="$MESSAGE" \\
    -e heading="$HEADING" \\
    -v $CERT_FILE:/etc/nginx/nginx.crt \\
    -v $KEY_FILE:/etc/nginx/nginx.key \\
    -p 8080:80 $(getImageName)"
}


stop() {
  runCommand "docker stop $containerName 2> /dev/null"
}

push() {
  local registry=$(getEcrRegistryName)
  local repo="$registry"
  local user="AWS"
  local pswd="$(aws ecr get-login-password --region $region)"

  if isDryrun ; then
    echo "$pswd | docker login -u $user --password-stdin $registry"
    echo "docker push $(getImageName)"
  else
    echo $pswd | docker login -u $user --password-stdin $registry
    docker push $(getImageName)
  fi
}

getEcrRegistryName() {
  if [ -n "$REGISTRY" ] ; then
    echo "$REGISTRY"
  else
    local accountId="$(aws sts get-caller-identity --output text --query 'Account')"
    [ -z "$accountId" ] && echo "Error retrieving account ID!" && exit 1
    REGISTRY="${accountId}.dkr.ecr.$region.amazonaws.com"
    echo "$REGISTRY"
  fi
}

getImageName() {
  echo $(getEcrRegistryName)/${imageShortName}:${imageTag}
}

runCommand() {
  isDryrun && echo "$1" || eval "$1"
}

checkCerts() {
  [ ! -d certs ] && mkdir certs
  cd certs
  
  if [ $(ls -1 | wc -l) -lt 3 ] ; then
    aws s3 sync s3://kuali-research-ec2-setup/$LANDSCAPE/certs/ .
  fi

  for f in $(ls -1) ; do
    if isAKeyFile $f ; then
      KEY_FILE=$(pwd)/$f
      windows && KEY_FILE="/$KEY_FILE"
    elif isACertFile $f && ! isAChainFile $f ; then
      CERT_FILE=$(pwd)/$f
      windows && CERT_FILE="/$CERT_FILE"
    fi
  done
}


task="$1"

shift

case "$task" in
  build)
    build ;;
  run)
    [ -z "$LANDSCAPE" ] && echo "Missing required parameter: Landscape" && exit 1
    run $@ ;;
  rerun)
    build && run $@ ;;
  stop)
    stop ;;
  push)
    push ;;
esac