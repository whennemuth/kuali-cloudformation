jobnames=(
  build-war
  build-image
  push-image
  deploy
)

declare -A jobs=()
jobs[${jobnames[0]}]='kuali-research-1-build-war'
jobs[${jobnames[1]}]='kuali-research-2-docker-build-image'
jobs[${jobnames[2]}]='kuali-research-3-docker-push-image'
jobs[${jobnames[3]}]='kuali-research-4-deploy-to-stack'

declare -A jobcalls=()

setGlobalVariables() {
  CLI=/var/lib/jenkins/jenkins-cli.jar
  HOST=http://localhost:8080/
  BRANCH=""

  if [ -z "$STACK_NAME" ] ; then
    echo "Missing entry! A stack must be selected."
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
  done <<< $(echo "$stackparts")

  if isSandbox ; then 
    BRANCH='master';
  elif isCI ; then 
    BRANCH='bu-master'; 
  fi

  # Prepare custom git references for manual feature builds and overriding of default git conventions        
  case "$GIT_REF_TYPE" in
    branch)
      GIT_REFSPEC="+refs/heads/$GIT_REF:refs/remotes/origin/$GIT_REF"
      GIT_BRANCHES_TO_BUILD="refs/heads/$GIT_REF"
      ;;
    tag)
      GIT_REFSPEC="+refs/tags/$GIT_REF:refs/remotes/origin/tags/$GIT_REF"
      GIT_BRANCHES_TO_BUILD="refs/tags/$GIT_REF"
      ;;
    *)
      GIT_REFSPEC="+refs/heads/*:refs/remotes/origin/*"
      GIT_BRANCHES_TO_BUILD="$GIT_COMMIT_ID"
      ;;        
  esac 
}

# Add a single parameter to the specified job call
addJobParm() {
  job=$1 && key=$2 && val=$3
  local temp=${jobcalls[$job]}
  # Add the "boilerplate" details if not already there: java command, jar, arguments, and switches.
  if [ -z "$temp" ] ; then
    temp="java -jar $CLI -s $HOST build '"${jobs[$job]}"' -v -f "
  fi
  # Add the parameter.
  if [ -n "$key" ] && [ -n "$val" ] ; then
    jobcalls[$job]="$temp -p $key=$val"
    if [ "$key" == "BRANCH" ] ; then
      # Set this particular variable for global visibility
      eval "$key=$val"
    fi
  fi
}

# Indicate if the default git reference was not taken (ie: "branch", "tag", or "commitID" was selected)
defaultGitRef() { [ "${GIT_REF_TYPE,,}" == "default" ] && true || false ; }
lastWar() { ls -1 /var/lib/jenkins/backup/kuali-research/war/$BRANCH/*.war 2> /dev/null ; }
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
    local originJob=${1:-'current'}
    originJob=${originJob,,}
    case $originJob in
      current)
        local pom="$(dirname $WORKSPACE)/${jobs['build-war']}/pom.xml"
        POM_VERSION="$(grep -Po '(?!<version>)[^<>]+</version>' $pom | head -n 1 | sed 's/<\/version>//')"
        ;;  
      prior)
        POM_VERSION="$(getPomVersionFromLastBuiltWar)"
        if [ -z "$POM_VERSION" ] ; then
          POM_VERSION="$(getPomVersionFromLastPushLog)"
        fi
        ;;
    esac
  fi
  if dryrun ; then
    local version=${POM_VERSION:-'[derived]'}
    local version=${POM_VERSION:-'unknown'}
  fi
  echo "$version"
}

# The last push o
getPomVersionFromLastPushLog() {
  local logfile="/var/lib/jenkins/jobs/${jobs['push-image']}/lastSuccessful/log"
  if [ -f "$logfile" ] ; then
    cat $logfile | grep -P 'digest' | cut -d ':' -f 1 | tr -d '[[:space:]]'
  fi
}

# The last built war file will have the pom version integrated in its name. 
getPomVersionFromLastBuiltWar() {
  echo "$(lastWar)" | grep -Po '(?<=coeus-webapp\-).*(?=\.war$)'
}

getEcrRepoName() {
  POM_ARTIFACTID='coeus'
  # Set the name of the target repository in docker registry
  if [ "$BRANCH" == "feature" ] ; then
    echo "$POM_ARTIFACTID-feature"
  elif [ "$BRANCH" == "master" ] ; then
    echo "$POM_ARTIFACTID-sandbox"
  else
    echo "$POM_ARTIFACTID"
  fi
}

buildWarJobCall() {
  local war=''

  if isSandbox; then
    war='true'
    addJobParm 'build-war' 'BRANCH' 'master'
    if ! defaultGitRef ; then
      addJobParm 'build-war' 'GIT_REFSPEC' $GIT_REFSPEC
      addJobParm 'build-war' 'GIT_BRANCHES_TO_BUILD' $GIT_BRANCHES_TO_BUILD
    fi
  elif isCI ; then
    war='true'
    if defaultGitRef ; then
      addJobParm 'build-war' 'BRANCH' $BRANCH
    else
      addJobParm 'build-war' 'BRANCH' 'feature'
      addJobParm 'build-war' 'GIT_REFSPEC' $GIT_REFSPEC
      addJobParm 'build-war' 'GIT_BRANCHES_TO_BUILD' $GIT_BRANCHES_TO_BUILD
    fi
  elif defaultGitRef ; then
    war='false'
    local pomVersion="$(getPomVersion 'prior')"
    if [ "$pomVersion" == 'unknown' ] ; then
      echo "PROBLEM!!! Cannot determine registry image to reference. POM version unknown!";
      echo "Cancelling build..."
      exit 1
    fi
  else
    war='true'
    isSandbox && local branch='master' || local branch='feature'
    addJobParm 'build-war' 'BRANCH' $branch
    addJobParm 'build-war' 'GIT_REFSPEC' $GIT_REFSPEC
    addJobParm 'build-war' 'GIT_BRANCHES_TO_BUILD' $GIT_BRANCHES_TO_BUILD
  fi

  [ "$war" == 'true' ] && true || false
}

buildDockerBuildImageJobCall() {
  addJobParm 'build-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'build-image' 'JENKINS_WAR_FILE' "\$(lastWar)"
  addJobParm 'build-image' 'REGISTRY_REPO_NAME' "$(getEcrRepoName)"
  addJobParm 'build-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
}

buildDockerPushImageJobCall() {
  addJobParm 'push-image' 'ECR_REGISTRY_URL' "$ECR_REGISTRY_URL"
  addJobParm 'push-image' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'push-image' 'REGISTRY_REPO_NAME' "$(getEcrRepoName)"
}

buildDeployJobCall() {
  addJobParm 'deploy' 'POM_VERSION' "\$(getPomVersion)"
  addJobParm 'deploy' 'STACK_NAME' "$STACK_NAME"
  addJobParm 'deploy' 'BASELINE' "$BASELINE"
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
  for jobname in ${jobnames[@]} ; do
    local jobcall="$(echo ${jobcalls[$jobname]} | sed 's/ -p/ \\\n  -p/g')"
    if [ -n "$jobcall" ] ; then
      echo ""
      echo "$jobcall"
    fi
  done
}

makeJobCalls() {
  local creds=/var/lib/jenkins/cli-credentials.sh
  [ -f $creds ] && source $creds
  for jobname in ${jobnames[@]} ; do
    local jobcall="${jobcalls[$jobname]}"
    if [ -n "$jobcall" ] ; then
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

  buildDeployJobCall

  if validParameters ; then
    callJobs
  fi
}

checkTestHarness $@ || true 2> /dev/null

run $@

