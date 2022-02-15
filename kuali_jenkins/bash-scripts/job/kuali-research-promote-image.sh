#!/bin/bash

# You must source common-functions.sh for some functionality used below.

checkTestHarness $@ 2> /dev/null || true

parseArgs $@

isDebug && set -x

validParameters() {
  local msg=""
  appendMessage() {
    [ -n "$msg" ] && msg="$msg, $1" || msg="$1"
  }

  echo "DEBUG=$DEBUG"
  echo "SOURCE_IMAGE=$SOURCE_IMAGE"
  echo "TARGET_IMAGE=$TARGET_IMAGEE"
  if [ -z "$ECR_REGISTRY_URL" ] ; then
    ECR_REGISTRY_URL="$(echo "$SOURCE_IMAGE" | cut -d'/' -f1 2> /dev/null)"
  fi
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"

  [ -z "$ECR_REGISTRY_URL" ] && appendMessage "ECR_REGISTRY_URL"
  [ -z "$SOURCE_IMAGE" ] && appendMessage "SOURCE_IMAGE"
  [ -z "$TARGET_IMAGE" ] && appendMessage "TARGET_IMAGE"

  [ -n "$msg" ] && echo "ERROR missing/invalid parameter(s): $msg"

  [ -z "$msg" ] && true || false
}

if validParameters ; then
  # Login to the registry
  region="$(echo $ECR_REGISTRY_URL | cut -d'.' -f4)"
  aws ecr get-login-password \
    --region $region \
    | docker login --username AWS --password-stdin ${ECR_REGISTRY_URL}

  # Pull the source image
  docker pull -q -a $SOURCE_IMAGE

  # Apply another tag to the source image
  docker tag $SOURCE_IMAGE $TARGET_IMAGE

  docker push $TARGET_IMAGE
fi
