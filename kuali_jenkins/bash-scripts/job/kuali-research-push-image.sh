#!/bin/bash

# You must source common-functions.sh for some functionality used below.

checkTestHarness $@ 2> /dev/null || true

parseArgs

isDebug && set -x

validParameters() {
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"
  echo "REGISTRY_REPO_NAME=$REGISTRY_REPO_NAME"
  echo "POM_VERSION=$POM_VERSION"
  DOCKER_TAG="${ECR_REGISTRY_URL}/${REGISTRY_REPO_NAME}:${POM_VERSION}"

  local msg=""
  appendMessage() {
    [ -n "$msg" ] && msg="$msg, $1" || msg="$1"
  }

  [ -z "$ECR_REGISTRY_URL" ] && appendMessage "ECR_REGISTRY_URL"
  [ -z "$REGISTRY_REPO_NAME" ] && appendMessage "REGISTRY_REPO_NAME"
  [ -z "$POM_VERSION" ] && appendMessage "POM_VERSION"

  [ -n "$msg" ] && echo "ERROR missing parameter(s): $msg"

  [ -z "$msg" ] && true || false
}


if validParameters() {
  aws ecr get-login-password \
    --region us-east-1 \
    | docker login --username AWS --password-stdin ${ECR_REGISTRY_URL}

  # Push the newly created image to the registry
  docker push ${DOCKER_TAG}
}
