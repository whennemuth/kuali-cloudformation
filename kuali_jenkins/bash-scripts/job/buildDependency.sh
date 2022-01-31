#!/bin/bash

parseArgs $@

isDebug && set -x

MODULE="$(echo "$GIT_REPO" | grep -oP '[^/]+.git$' | sed 's/kuali-//g' | cut -d'.' -f1 2> /dev/null)"

validParameters() {
  outputSubHeading "${MODULE:-"UKNOWN"} build parameters:"
  local msg=""
  appendMessage() {
    [ -n "$msg" ] && msg="$msg, $1" || msg="$1"
  }
  
  JENKINS_HOME=${JENKINS_HOME:-"/var/lib/jenkins"}
  [ ! -d "$JENKINS_HOME" ] && appendMessage 'JENKINS_HOME'
  [ -z "$GIT_REPO" ] && appendMessage 'GIT_REPO'
  [ -z "$GIT_DEPLOY_KEY" ] && appendMessage 'GIT_DEPLOY_KEY'
  if [ -z "$msg" ] ; then
    if [ -n "$MODULE" ] ; then
      if [ -n "$MAVEN_WORKSPACE" ] ; then
        MAVEN_WORKSPACE=$(dirname $MAVEN_WORKSPACE)/$MODULE
      else
        MAVEN_WORKSPACE="$JENKINS_HOME/latest-maven-build/$MODULE"
      fi
    else
      MAVEN_WORKSPACE=""
    fi
  fi
  [ -z "$MAVEN_WORKSPACE" ] && appendMessage 'MAVEN_WORKSPACE'

  outputSubHeading "Parameters:"
  #-----------------------------------------------------------------------
  # These take priority in the following order: branch, tag, and/or commit 
  #-----------------------------------------------------------------------
  echo "GIT_BRANCH=$GIT_BRANCH"
  echo "GIT_TAG=$GIT_TAG"
  echo "GIT_COMMIT=$GIT_COMMIT"
  #-----------------------------------------------------------------------
  echo "GIT_REPO=$GIT_REPO"
  echo "GIT_DEPLOY_KEY=$GIT_DEPLOY_KEY"
  echo "JENKINS_HOME=$JENKINS_HOME"
  echo "MAVEN_WORKSPACE=$MAVEN_WORKSPACE"
  echo " "
 
  [ -n "$msg" ] && echo "ERROR missing/invalid parameter(s): $msg"

  [ -z "$msg" ] && true || false
}

pullFromGithub() {
  [ -n "$GIT_COMMIT" ] && local reftype='commit'
  [ -n "$GIT_TAG" ] && local reftype='tag'
  [ -n "$GIT_BRANCH" ] && local reftype='branch'
  local ref="${GIT_BRANCH:-${GIT_TAG:-${GIT_COMMIT}}}"
  outputSubHeading "Fetching $reftype \"$ref\" from $GIT_REPO ..."
  (
    githubFetchAndReset \
      "rootdir=$MAVEN_WORKSPACE" \
      "repo=$GIT_REPO" \
      "key=$GIT_DEPLOY_KEY" \
      "reftype=$reftype" \
      "ref=$ref" \
      "commit=$GIT_COMMIT" \
      "user=jenkins@bu.edu"
  )
  [ $? -eq 0 ] && true || false
}

performMavenBuild() {
  outputSubHeading "$MODULE: Performing maven build..."
  buildingRice() {
    [ -n "$(echo "${MODULE,,}" | grep -o 'rice')" ] && true || false
  }
  (
    cd $MAVEN_WORKSPACE
    if buildingRice ; then
      mvn clean compile install -e -Dgrm.off=true
    else
      mvn clean compile install -Dgrm.off=true -Dmaven.test.skip=true
    fi
  )
}

if validParameters ; then

  pullFromGithub

  performMavenBuild
fi