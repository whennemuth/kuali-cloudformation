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

outputHeadingCounter=1

declare -A jobScripts=()
jobScriptDir=${JOB_SCRIPT_DIR:-"$JENKINS_HOME/kuali-infrastructure/kuali_jenkins/bash-scripts/job"}
jobScripts[${jobIDs[0]}]="$jobScriptDir/kuali-research-build-war.sh"
jobScripts[${jobIDs[1]}]="$jobScriptDir/kuali-research-build-image.sh"
jobScripts[${jobIDs[2]}]="$jobScriptDir/kuali-research-push-image.sh"
jobScripts[${jobIDs[3]}]="$jobScriptDir/kuali-research-promote-image.sh"
jobScripts[${jobIDs[4]}]="$jobScriptDir/kuali-research-deploy.sh"

declare -A jobcalls=()

setGlobalVariables() {
  CLI=$JENKINS_HOME/jenkins-cli.jar
  HOST=http://localhost:8080/
  BUILD_TYPE="${BUILD_TYPE,,}"
  MAVEN_WORKSPACE="$JENKINS_HOME/latest-maven-build/kc"
  ([ "${LEGACY_DEPLOY,,}" == 'staging' ] || [ "${LEGACY_DEPLOY,,}" == 'stage' ]) && LEGACY_DEPLOY='stg'
  [ "${LEGACY_DEPLOY,,}" == 'production' ] && LEGACY_DEPLOY='prod'

  if [ -n "$STACK" ] ; then
    # The STACK parameter is actually 3 values: stack name, baseline, and landscape concatenated together with a pipe character
    local stackparts=$(echo $STACK | awk 'BEGIN {RS="|"} {print $0}')
    local counter=1
    while read part; do
      case $((counter++)) in
        1) STACK_NAME="$part" ;;
        2) BASELINE="$part" ;;
        3) LANDSCAPE="$part" ;;
      esac
    done <<< "$(echo "$stackparts")"
  fi

  if [ -z "$BUILD_TYPE" ] ; then
    echo "Missing entry! A build type must be selected."
    echo "Cancelling build..."
    exit 1
  elif [ -z "$LANDSCAPE" ] && isFeatureBuild ; then
    echo "Missing entry! A stack must be selected when performing a feature build."
    echo "Cancelling build..."
    exit 1
  fi

  if isRelease || isPreRelease ; then
    isSandbox && BRANCH='master' || BRANCH='bu-master'
  else
    BRANCH='feature'
  fi

  BACKUP_DIR="$JENKINS_HOME/backup/kuali-research/war/$BRANCH"

  outputSubHeading "Parameters:"
  echo "MAVEN_WORKSPACE=$MAVEN_WORKSPACE"
  echo "BACKUP_DIR=$BACKUP_DIR"
  echo "BRANCH=$BRANCH"
  echo "BUILD_TYPE=$BUILD_TYPE"
  echo "LEGACY_DEPLOY=$LEGACY_DEPLOY"
  echo "GIT_REF_TYPE=$GIT_REF_TYPE"
  echo "GIT_REF=$GIT_REF"
  echo "GIT_COMMIT_ID=$GIT_COMMIT_ID"
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"
  echo "LANDSCAPE=$LANDSCAPE"
  echo "BASELINE=$BASELINE"
  echo "STACK_NAME=$STACK_NAME"
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

isStackSelected() { [ -n "$STACK_NAME" ] && true || false ; }
isJenkinsServer() { [ -d /var/lib/jenkins ] && true || false ; }
isFeatureBuild() { [ "$BUILD_TYPE" == "feature" ] && true || false ; }
isPreRelease() { [ "$BUILD_TYPE" == "pre-release" ] && true || false ; }
isRelease() { [ "$BUILD_TYPE" == "release" ] && true || false ; }
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

  getPomVersionFromYoungestRegistryImage() {
    getYoungestRegistryImage 'promote-from' | cut -d':' -f2
  }

  if [ -z "$POM_VERSION" ] ; then
    if isFeatureBuild ; then
      # Get the pom version of what is currently being built
      local pom="$MAVEN_WORKSPACE/pom.xml"
      POM_VERSION="$(grep -Po '(?!<version>)[^<>]+</version>' $pom | head -n 1 | sed 's/<\/version>//')"
    else
      POM_VERSION="$(getPomVersionFromYoungestRegistryImage)"
    fi
  fi
  local version=${POM_VERSION:-'unknown'}
  echo "$version"
}

# Get the name of the ecr non-release repository from where images exist to be pulled so as to "promote" them in a follow-up pushes to the release repository.
getPullEcrRepoName() {
  local repo='kuali-coeus'
  if [ "$BRANCH" == "master" ] ; then
    echo "$repo-sandbox"
  elif isFeatureBuild || isPreRelease ; then
    echo "$repo-feature"
  elif isRelease ; then
    echo "Not_Applicable"
  fi
}

# Get the name of the ecr release repository where images get pushed to in "promotions" from non-release repositories.
getPushEcrRepoName() {
  local repo='kuali-coeus'
  # Set the name of the target repository in docker registry
  if [ "$BRANCH" == "master" ] ; then
    echo "$repo-sandbox"
  elif isFeatureBuild ; then
    echo "$repo-feature"
  elif isPreRelease || isRelease ; then
    echo "$repo"
  fi
}

# Select from all images in the coeus ecr repository tagged with a maven-style version (ie: "2001.0040"), where such tag indicates the latest version.
getYoungestRegistryImage() {
  local type="$1"
  case "${type,,}" in
    promote-from) local repo="$(getPullEcrRepoName)" ;;
    promote-to) 
      local repo="$(getPushEcrRepoName)"
      if isPreRelease || isRelease ; then
        local release='true' 
      fi
      ;;
  esac

  getLatestImage "repo_name=$repo" "account_nbr=$acct" "release=$release"
}

buildWarJobCall() {
  local built='false'

  if isFeatureBuild || isPreRelease ; then
    if isFeatureBuild ; then
      if isProd ; then
        echo "INVALID CHOICE: Feature builds not allowed against the production environment!"
        exit 1
      elif isStaging ; then
        echo "WARNING: You are pushing a feature build directly into the staging environment!"
      fi
    elif isProd ; then
      echo "INVALID CHOICE: Pre-releases not allowed against the production environment!"
      exit 1
    fi
    built='true'
    addJobParm 'build-war' 'DEBUG' $DEBUG
    addJobParm 'build-war' 'BRANCH' $BRANCH
    addJobParm 'build-war' 'GIT_REF_TYPE' $GIT_REF_TYPE
    addJobParm 'build-war' 'GIT_REF' $GIT_REF    
    addJobParm 'build-war' 'GIT_COMMIT_ID' $GIT_COMMIT_ID
    addJobParm 'build-war' 'MAVEN_WORKSPACE' $MAVEN_WORKSPACE
    addJobParm 'build-war' 'BACKUP_DIR' $BACKUP_DIR
  fi

  [ "$built" == 'true' ] && true || false
}

buildDockerBuildImageJobCall() {
  addJobParm 'build-image' 'DEBUG' "$DEBUG"
  addJobParm 'build-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'build-image' 'JENKINS_WAR_FILE' "\$(lastWar)"
  addJobParm 'build-image' 'REGISTRY_REPO_NAME' "$(getPushEcrRepoName)"
  addJobParm 'build-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
  # This file should be there as long as the -Dcopy.javaagent.off arg is not set to true when running mvn
  addJobParm 'build-image' 'SPRING_INSTRUMENT_JAR' "$MAVEN_WORKSPACE/target/javaagent/spring-instrument.jar"
}

buildDockerPushImageJobCall() {
  addJobParm 'push-image' 'DEBUG' "$DEBUG"
  addJobParm 'push-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
  addJobParm 'push-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'push-image' 'REGISTRY_REPO_NAME' "$(getPushEcrRepoName)"
}

buildPromoteDockerImageJobCall() {
  addJobParm 'promote-image' 'DEBUG' "$DEBUG"
  addJobParm 'promote-image' 'SOURCE_IMAGE' "$(getYoungestRegistryImage 'promote-from')"
  addJobParm 'promote-image' 'TARGET_IMAGE' "$(getYoungestRegistryImage 'promote-to')"
}

buildDeployJobCall() {
  addJobParm 'deploy' 'DEBUG' "$DEBUG"
  addJobParm 'deploy' 'DRYRUN' "$DEBUG"
  addJobParm 'deploy' 'STACK_NAME' "\"$STACK_NAME\""
  addJobParm 'deploy' 'LANDSCAPE' "$LANDSCAPE"
  addJobParm 'deploy' 'REMOTE_DEBUG' "$REMOTE_DEBUG"
  addJobParm 'deploy' 'NEW_RELIC_LOGGING' "$(newrelic && echo 'true' || echo 'false')"
  addJobParm 'deploy' 'TARGET_IMAGE' "$(getYoungestRegistryImage 'promote-to')"
}

buildLegacyDeployJobCall() {
  addJobParm 'deploy' 'DEBUG' "$DEBUG"
  addJobParm 'deploy' 'DRYRUN' "$DEBUG"
  addJobParm 'deploy' 'STACK_NAME' "legacy"
  addJobParm 'deploy' 'LANDSCAPE' "$LANDSCAPE"
  addJobParm 'deploy' 'REMOTE_DEBUG' "$REMOTE_DEBUG"
  addJobParm 'deploy' 'NEW_RELIC_LOGGING' "$(newrelic && echo 'true' || echo 'false')"
  addJobParm 'deploy' 'TARGET_IMAGE' "$(getYoungestRegistryImage 'promote-to' $LEGACY_DEPLOY)"
  addJobParm 'deploy' 'LEGACY_LANDSCAPE' "$LEGACY_DEPLOY"
  addJobParm 'deploy' 'CROSS_ACCOUNT_ROLE_ARN' "arn:aws:iam::730096353738:role/kuali-ssm-trusting-role"
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
  set -e
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
  true
}

legacyDeployStaging() {
  [ "${LEGACY_DEPLOY,,}" == 'stg' ] && true || false
}
legacyDeployProduction() {
  [ "${LEGACY_DEPLOY,,}" == 'prod' ] && true || false
}
legacyDeploy() {
  (legacyDeployStaging || legacyDeployProduction) && true || false
}


run() {
  setGlobalVariables

  if buildWarJobCall ; then

    buildDockerBuildImageJobCall

    buildDockerPushImageJobCall
  fi

  # if isPreRelease ; then

  #   buildPromoteDockerImageJobCall
  # fi

  if isStackSelected ; then
    buildDeployJobCall
  fi

  if validParameters ; then
    callJobs
  fi

  if legacyDeploy ; then
    # Wait for a minute or two to give the cross-account ecr image replication a chance to finish
    waitForLegacyEcrUpdate() {
      local sleep=5
      local timeoutSeconds=120
      local counter=0
      echo "Waiting for $timeoutSeconds seconds to give the cross-account ecr image replication a chance to finish..."
      set +e
      while true ; do
        [ $(($counter*$sleep)) -ge $timeoutSeconds ] && echo "$timeoutSeconds elapsed, starting to deploy to legacy account..." && break;
        echo "$((timeoutSeconds-$(($counter*$sleep)))) seconds remaining..."
        ((counter++))
        sleep $sleep      
      done
      echo " "
      set -e
    }

    if isStackSelected ; then
      if isDryrun ; then
        echo "Wait for legacy ECR to update..."
      else
        waitForLegacyEcrUpdate
      fi
    fi

    # Clear out the exiting built jobs, create one for the legacy deploy and run it.
    STACK_NAME='legacy'
    declare -A jobcalls=()
    buildLegacyDeployJobCall
    callJobs
  fi
}

checkTestHarness $@ 2> /dev/null || true

isDebug && set -x

run $@

