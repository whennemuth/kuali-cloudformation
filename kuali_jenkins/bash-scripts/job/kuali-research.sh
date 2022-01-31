#!/bin/bash

# trap 
# http://linuxcommand.org/lc3_wss0150.php
# https://medium.com/@dirk.avery/the-bash-trap-trap-ce6083f36700
# TEMP_FILE="$TEMP_DIR/$PROGNAME.$$.$RANDOM"

set -a

jobIDs=(
  build-war
  build-image
  push-image
  promote-image
  deploy
)

declare -A jobScripts=()
jobScriptDir=${JOB_SCRIPT_DIR:-"$JENKINS_HOME/kuali-infrastructure/kuali_jenkins/bash-scripts/job"}
jobScripts[${jobIDs[0]}]="$jobScriptDir/kuali-research-build-war.sh"
jobScripts[${jobIDs[1]}]="$jobScriptDir/kuali-research-build-image.sh"
jobScripts[${jobIDs[2]}]="$jobScriptDir/kuali-research-push-image.sh"
jobScripts[${jobIDs[3]}]="$jobScriptDir/kuali-research-promote-image.sh"
jobScripts[${jobIDs[4]}]="$jobScriptDir/kuali-research-deploy.sh"

declare -A jobNames=()
jobNames[${jobIDs[0]}]='kuali-research-1-build-war'
jobNames[${jobIDs[1]}]='kuali-research-2-docker-build-image'
jobNames[${jobIDs[2]}]='kuali-research-3-docker-push-image'
jobNames[${jobIDs[3]}]='none'
jobNames[${jobIDs[4]}]='kuali-research-4-deploy-to-stack'

declare -A jobcalls=()

setGlobalVariables() {
  CLI=$JENKINS_HOME/jenkins-cli.jar
  HOST=http://localhost:8080/

  if [ -z "$STACK" ] ; then
    echo "Missing entry! A stack must be selected."
    echo "Cancelling build..."
    exit 1
  elif [ -z "$BUILD_TYPE" ] ; then
    echo "Missing entry! A build type must be selected."
    echo "Cancelling build..."
    exit 1
  fi

  # The STACk parameter is actually 3 values: stack name, baseline, and landscape concatenated together with a pipe character
  local stackparts=$(echo $STACK | awk 'BEGIN {RS="|"} {print $0}')
  local counter=1
  while read part; do
    case $((counter++)) in
      1) STACK_NAME="$part" ;;
      2) BASELINE="$part" ;;
      3) LANDSCAPE="$part" ;;
    esac
  done <<< "$(echo "$stackparts")"

  if isReleaseBuild || isPreReleaseBuild ; then
    isSandbox && BRANCH='master' || BRANCH='bu-master'
  else
    BRANCH='feature'
  fi

  BUILD_TYPE="${BUILD_TYPE,,}"
  MAVEN_WORKSPACE="$JENKINS_HOME/latest-maven-build/kc"
  BACKUP_DIR="$JENKINS_HOME/backup/kuali-research/war/$BRANCH"

  outputSubHeading "Parameters:"
  echo "MAVEN_WORKSPACE=$MAVEN_WORKSPACE"
  echo "BACKUP_DIR=$BACKUP_DIR"
  echo "BRANCH=$BRANCH"
  echo "BUILD_TYPE=$BUILD_TYPE"
  echo "GIT_REF_TYPE=$GIT_REF_TYPE"
  echo "GIT_REF=$GIT_REF"
  echo "GIT_COMMIT_ID=$GIT_COMMIT_ID"
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"
  echo " "
}

# Add a single parameter to the specified job call
addJobParm() {
  job=$1 && key=$2 && val=$3
  local temp=${jobcalls[$job]}
  # Add the "boilerplate" details if not already there: java command, jar, arguments, and switches.
  if [ -z "$temp" ] ; then
    temp="sh -e -a ${jobScripts[$job]} "
  fi
  # Add the parameter.
  if [ -n "$key" ] && [ -n "$val" ] ; then
    jobcalls[$job]="$temp $key=$val"
    if [ "$key" == "BRANCH" ] ; then
      # Set this particular variable for global visibility
      eval "$key=$val"
    fi
  fi
}

isJenkinsServer() { [ -d /var/lib/jenkins ] && true || false ; }
isFeatureBuild() { [ "$BUILD_TYPE" == "feature" ] && true || false ; }
isPreReleaseBuild() { [ "$BUILD_TYPE" == "pre-release" ] && true || false ; }
isReleaseBuild() { [ "$BUILD_TYPE" == "release" ] && true || false ; }
lastWar() { find $BACKUP_DIR -iname coeus-webapp-*.war 2> /dev/null ; }
isSandbox() { [ "${LANDSCAPE,,}" == "sandbox" ] && true || false ; }
isCI() { [ "${LANDSCAPE,,}" == "ci" ] && true || false ; }
isStaging() { ([ "${LANDSCAPE,,}" == "stg" ] || [ "${LANDSCAPE,,}" == "stage" ] || [ "${LANDSCAPE,,}" == "staging" ]) && true || false ; }
isProd() { ([ "${LANDSCAPE,,}" == "prod" ] || [ "${LANDSCAPE,,}" == "production" ]) && true || false ; }
newrelic() { isStaging || isProd ; }
# Print out the calls this job would make to other jobs, but do not execute those calls.
dryrun() { [ "$DRYRUN" == true ] && true || false ; }
# Make all standard output verbose with set -x
debug() { [ "$DEBUG" == true ] && true || false ; }
# Perform the appropriate action with the built job calls
callJobs() { if dryrun ; then printJobCalls; else makeJobCalls; fi }

getPomVersion() {
  if [ -z "$POM_VERSION" ] ; then
    if isFeatureBuild ; then
      # Get the pom version of what is currently being built
      local pom="$MAVEN_WORKSPACE/pom.xml"
      POM_VERSION="$(grep -Po '(?!<version>)[^<>]+</version>' $pom | head -n 1 | sed 's/<\/version>//')"
    else
      POM_VERSION="$(getPomVersionFromYoungestRegistryImage)"
      # Get the pom version of what has already been built by a prior job
      # POM_VERSION="$(getPomVersionFromLastBuiltWar)"
      # if [ -z "$POM_VERSION" ] ; then
      #   POM_VERSION="$(getPomVersionFromLastPushLog)"
      #   if [ -z "$POM_VERSION" ] ; then
      #     POM_VERSION="$(getPomVersionFromYoungestRegistryImage)"
      #   fi
      # fi
    fi
  fi
  # if dryrun ; then
  #   local version=${POM_VERSION:-'[derived]'}
  # else
  #   local version=${POM_VERSION:-'unknown'}
  # fi
  local version=${POM_VERSION:-'unknown'}
  echo "$version"
}

# The last push o
getPomVersionFromLastPushLog() {
  local logfile="/var/lib/jenkins/jobs/${jobNames['push-image']}/lastSuccessful/log"
  if [ -f "$logfile" ] ; then
    cat $logfile | grep -P 'digest' | cut -d ':' -f 1 | tr -d '[[:space:]]'
  fi
}

# The last built war file will have the pom version integrated in its name. 
getPomVersionFromLastBuiltWar() {
  echo "$(lastWar)" | grep -Po '(?<=coeus-webapp\-).*(?=\.war$)'
}

getYoungestRegistryImage() {
  local repo="${1:-$(getEcrRepoName)}"
  local acct="aws sts get-caller-identity --output text --query 'Account'"
  getLatestImage "$repo" "$acct"
}

getPomVersionFromYoungestRegistryImage() {
  getYoungestRegistryImage | cut -d':' -f2
}

getEcrRepoName() {
  local repo=='kuali-coeus'
  # Set the name of the target repository in docker registry
  if [ "$BRANCH" == "master" ] ; then
    echo "$repo-sandbox"
  elif isFeatureBuild || isPreReleaseBuild ; then
    echo "$repo-feature"
  elif isReleaseBuild ; then
    echo "$repo"
  fi
}

buildWarJobCall() {
  local built='false'

  if isFeatureBuild ; then
    if isProd ; then
      echo "INVALID CHOICE: Feature builds not allowed against the production environment!"
      exit 1
    elif isStaging ; then
      echo "WARNING: You are pushing a feature build directly into the staging environment!"
    fi
    built='true'
    addJobParm 'build-war' 'DEBUG' "$DEBUG"
    addJobParm 'build-war' 'BRANCH' $BRANCH
    addJobParm 'build-war' 'GIT_REF_TYPE' $GIT_REF_TYPE
    addJobParm 'build-war' 'GIT_REF' $GIT_REF    
    addJobParm 'build-war' 'GIT_COMMIT_ID' $GIT_COMMIT_ID
    addJobParm 'build-war' 'MAVEN_WORKSPACE' "$MAVEN_WORKSPACE" 
    addJobParm 'build-war' 'BACKUP_DIR' "$BACKUP_DIR"
  else
    local pomVersion="$(getPomVersion)"
    if [ "$pomVersion" == 'unknown' ] ; then
      echo "PROBLEM!!! Cannot determine registry image to reference. POM version unknown!";
      echo "Cancelling build..."
      exit 1
    fi
  fi

  [ "$built" == 'true' ] && true || false
}

buildDockerBuildImageJobCall() {
  addJobParm 'build-image' 'DEBUG' "$DEBUG"
  addJobParm 'build-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'build-image' 'JENKINS_WAR_FILE' "\$(lastWar)"
  addJobParm 'build-image' 'REGISTRY_REPO_NAME' "$(getEcrRepoName)"
  addJobParm 'build-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
}

buildDockerPushImageJobCall() {
  addJobParm 'push-image' 'DEBUG' "$DEBUG"
  addJobParm 'push-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
  addJobParm 'push-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'push-image' 'REGISTRY_REPO_NAME' "$(getEcrRepoName)"
}

buildPromoteDockerImageJobCall() {
  addJobParm 'promote-image' 'DEBUG' "$DEBUG"
  addJobParm 'promote-image' 'SOURCE-IMAGE' "$(getYoungestRegistryImage)"
  addJobParm 'promote-image' 'TARGET-IMAGE' "$(getYoungestRegistryImage 'kuali-coeus')"
}

buildDeployJobCall() {
  if isFeatureBuild ; then
    addJobParm 'deploy' 'POM_VERSION' "\$(getPomVersion)"
  elif isReleaseBuild ; then
    addJobParm 'deploy' 'POM_VERSION' "$(getPomVersion 2> /dev/null)"
  fi
  addJobParm 'deploy' 'STACK_NAME' "\"$STACK_NAME\""
  # addJobParm 'deploy' 'BASELINE' "$BASELINE"
  addJobParm 'deploy' 'DEBUG' "$DEBUG"
  addJobParm 'deploy' 'LANDSCAPE' "$LANDSCAPE"
  addJobParm 'deploy' 'NEW_RELIC_LOGGING' "$(newrelic && echo 'true' || echo 'false')"
  addJobParm 'deploy' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
  addJobParm 'deploy' 'REGISTRY_REPO_NAME' "$(getEcrRepoName)"
  if [ -n "POM_ARTIFACTID_OVERRIDE" ] ; then
    # By convention, we are calling the repository name within the registry the same as the artifactId of the pom file 
    # that the repository keeps images for. However if we want to break this rule and cause downstream jobs to push 
    # and pull from the registry referencing a different repository name, then set this value accordingly.
    addJobParm 'deploy' 'POM_ARTIFACTID_OVERRIDE' $POM_ARTIFACTID_OVERRIDE
  fi
}

printJobCalls() {
  for jobId in ${jobIDs[@]} ; do
    local jobcall="$(echo ${jobcalls[$jobId]} | sed 's/ -p/ \\\n  -p/g')"
    if [ -n "$jobcall" ] ; then
      echo ""
      echo "$jobcall" | sed -E 's/\x20/ \\\n  /g'
    fi
  done
  echo ""
}

makeJobCalls() {
  local creds=/var/lib/jenkins/cli-credentials.sh
  [ -f $creds ] && source $creds
  for jobId in ${jobIDs[@]} ; do
    local jobcall="${jobcalls[$jobId]}"
    if [ -n "$jobcall" ] ; then
      outputHeading "Invoking $jobId..."
      echo ""
      echo "$jobcall" | sed -E 's/\x20/ \\\n  /g'
      echo ""
      eval "$jobcall"
    fi
  done
}

validParameters() {
  local msg=''
  [ -z "$LANDSCAPE" ] && msg="no landscape selection"
  if [ -n "$msg" ] ; then
    echo "Invalid/missing parameters: $msg"
  fi
  [ -z "$msg" ] && true || false
}



run() {
  setGlobalVariables

  if buildWarJobCall ; then

    buildDockerBuildImageJobCall

    buildDockerPushImageJobCall
  fi

  if isPreReleaseBuild ; then

    buildPromoteDockerImageJobCall
  fi

  buildDeployJobCall

  if validParameters ; then
    callJobs
  fi
}

checkTestHarness $@ 2> /dev/null || true

isDebug && set -x

run $@

