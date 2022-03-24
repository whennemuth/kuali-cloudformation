#!/bin/bash
  
urldecode() {
  local url_encoded="${1//+/ }"
  printf '%b' "${url_encoded//%/\\x}"
}

# Parameters are all combined into a single querystring. Split them up into separate shell variables.
processParametersQueryString() {
  outputHeading 'Breaking down parameter querystring...'
  # Get rid of commas
  PARAMETERS="$(echo "$PARAMETERS" | sed 's/,//g')"
  # Replace url encoded newlines with special placeholders
  newline='<-newline->'
  PARAMETERS="$(echo "$PARAMETERS" | sed 's/%0A/'$newline'/g')"
  if [ -z "$PARAMETERS" ] ; then
    echo "No Parameters!"
    exit 1
  else 
    echo "PARAMETERS: $PARAMETERS
    "
  fi
  
  # Load the querystring into variables.
  echo "Parsing...
  "
  processPair() {
    local name="$1"
    local value="$2"
    value="$(urldecode "$value")"
    local cmd="${name^^}=\"$value\""
    echo "$cmd"
    eval "$cmd"
  }
  valueIsMultiLine() {
     [ -n "$(echo "$1" | grep "$newline")" ] && true || false
  }
  for pair in $(echo "$PARAMETERS" | awk 'BEGIN {RS="&"} {print $1}') ; do
    local name="$(echo "$pair" | cut -d'=' -f1)"
    local value="$(echo "$pair" | cut -d'=' -f2)"
    if valueIsMultiLine "$value" ; then
      value="$(urldecode "$value")"
      local origValue="$(echo "$value" | sed 's/'$newline'/%0A/g')"
      processPair "$name" "$origValue"
      for subpair in $(echo "$value" | awk 'BEGIN {RS="'$newline'"} {print $1}') ; do
        local subname="$(echo "$subpair" | cut -d'=' -f1)"
        local subvalue="$(echo "$subpair" | cut -d'=' -f2)"
        processPair "$subname" "$subvalue"
      done
    else
      processPair "$name" "$value"
    fi
  done
}

validateChoices() {
  outputHeading 'Validating parameter choices...'
  if [ -z "$STACK_ACTION" ] ; then
    echo "MISSING: STACK_ACTION"
    exit 1
  fi
  if [ "$STACK_ACTION" == 'create' ] && [ -z "$STACK_TYPE" ] ; then
    echo "MISSING: STACK_TYPE"
    exit 1
  fi
  if [ -z "$RDS_SOURCE" ] && [ "$STACK_ACTION" != 'delete' ] ; then
    err "MISSING: RDS_SOURCE"
    exit 1
  fi
  [ 'empty' == "${RDS_INSTANCE_BY_LANDSCAPE,,}" ] && RDS_INSTANCE_BY_LANDSCAPE=''
  [ 'empty' == "${RDS_INSTANCE_BY_BASELINE,,}" ] && RDS_INSTANCE_BY_BASELINE=''
  [ 'empty' == "${RDS_SNAPSHOT_ORPHANS,,}" ] && RDS_SNAPSHOT_ORPHANS=''
  [ 'empty' == "${RDS_SNAPSHOT_SHARED,,}" ] && RDS_SNAPSHOT_SHARED=''
  [ 'empty' == "${RDS_SNAPSHOT,,}" ] && RDS_SNAPSHOT=''
  echo "Parameter choices ok."
}

# Build the arguments to be passed to the stack creation/deletion function call in the main script pulled from git
buildArgs() {
  local args=()
  
  putArg() {
    local name="$(echo "$1" | cut -d'=' -f1)"
    local value="$(echo "$1" | cut -d'=' -f2)"
    local required=${2:-'true'}
    if [ -z "$value" ] && [ $required == 'true' ] ; then
      err "Missing parameter value!: $name"
      exit 1
    fi
    if [ -n "$value" ] ; then
      local pair="${name^^}="$value""
      echo "$pair"
      eval "$pair"
      args=(${args[@]} $pair)
    fi
    [ -n "$value" ] && true || false
  }

  # The STACK parameter is actually 3 values: stack name, baseline, and landscape concatenated together with a pipe character
  splitStack() {
    local stackparts="$(echo $STACK | awk 'BEGIN {RS="|"} {print $0}')"
    local counter=1
    while read part; do
      case $((counter++)) in
        1) STACK_NAME="$part" ;;
        2) BASELINE="$part" ;;
        3) LANDSCAPE="$part" ;;
      esac
    done <<< "$(echo "$stackparts")"
  }
  getStackName() {
    [ -z "$STACK_NAME" ] && splitStack
    echo "$STACK_NAME"
  }
  getBaseline() {
    [ -z "$BASELINE" ] && splitStack
    echo "$BASELINE"
  }
  getLandscape() {
    [ -z "$LANDSCAPE" ] && splitStack
    echo "$LANDSCAPE"
  }
  
  for parm in $@ ; do
    case $parm in
      STACK) 
        putArg FULL_STACK_NAME=$(getStackName) || true ;;
      LANDSCAPE) 
        putArg LANDSCAPE=$(getLandscape) || true ;;
      AUTHENTICATION)
        local shib='false'
        [ "${AUTHENTICATION,,}" == 'shibboleth' ] && shib='true'
        putArg USING_SHIBBOLETH=$shib || true
        ;;
      DNS)
        local route53='false'
        [ "${DNS,,}" == 'route53' ] && route53='true'
        putArg USING_ROUTE53=$route53 || true
        ;;
      WAF)
        putArg CREATE_WAF=$WAF 'false' || true ;;
      ALB)
        putArg ENABLE_ALB_LOGGING=$ALB 'false' || true ;;
      MONGO)
        putArg CREATE_MONGO=$MONGO || true ;;
      RDS_SOURCE)
        case "${RDS_SOURCE,,}" in
          instance)
            if putArg RDS_ARN=$(urldecode $RDS_INSTANCE_BY_LANDSCAPE) 'false' ; then
              local rdsval='true'
            fi
            ;;
          owned-snapshot)
            local snapshotArn="$(urldecode $RDS_SNAPSHOT)"
            if [ -n "$snapshotArn" ] && [ ${#snapshotArn} -gt 10 ] ; then
              # If greater than 10 characters then it must be an arn, not a word like 'none' or 'new' or 'empty'
              if putArg RDS_SNAPSHOT_ARN="$snapshotArn" 'false' ; then
                local rdsval='true'
              fi
            else
              if putArg RDS_ARN_TO_CLONE="$(urldecode $RDS_INSTANCE_BY_BASELINE)" 'false' ; then
                local rdsval='true'
              fi
            fi
            ;;
          orphaned-snapshot)
            if putArg RDS_SNAPSHOT_ARN=$(urldecode $RDS_SNAPSHOT_ORPHANS) 'false' ; then
              local rdsval='true'
            fi
            ;;
          shared-snapshot)
            if putArg RDS_SNAPSHOT_ARN=$(urldecode $RDS_SNAPSHOT_SHARED) 'false' ; then
              local rdsval='true'
            fi
            ;;
        esac
        if [ "$rdsval" != 'true' ] ; then
          echo "MISSING PARAMETER: No RDS instance or snapshotting information has been included."
          exit 1
        fi
        ;;
      ADVANCED)
        putArg RETAIN_LAMBDA_CLEANUP_LOGS=$ADVANCED_KEEP_LAMBDA_LOGS 'false' || true
        if [ -n "$ADVANCED_MANUAL_ENTRIES" ] ; then
          while read line ; do
            local pair=($(echo $line | sed 's/=/ /g'))
            if [ ${#pair[@]} -eq 2 ] ; then
              putArg "$line" || true
            else
              echo "BAD MANUAL ENTRY - MUST FOLLOW KEY=VALUE"
              exit 1
            fi
          done <<< "$(urldecode $ADVANCED_MANUAL_ENTRIES)"
        fi
        ;;
    esac
  done
  
  # [ -z "$SKIP_S3_UPLOAD" ] && putArg SKIP_S3_UPLOAD=true || true
  [ -z "$DEEP_VALIDATION" ] && putArg DEEP_VALIDATION=false || true
  [ -z "$PROMPT" ] && putArg PROMPT=false || true
  isDebug && putArg DEBUG=true || true
  isDryrun && putArg DRYRUN=true || true
  # Since the user can pick a different stack type (ec2, ec2-alb, ecs), the name of the stack to delete may not be the name of the stack it gets recreated as.
  [ "$STACK_ACTION" == 'recreate' ] && [ -n "$STACK" ] && putArg STACK_TO_DELETE=$(getStackName) || true
} 


pullCodeFromGithub() {
  echo 'Pulling kuali-infrastructure github repository...'
  source $JENKINS_HOME/cli-credentials.sh
  java -jar $JENKINS_HOME/jenkins-cli.jar -s http://localhost:8080/ build fetch-and-reset-kuali-infrastructure -v -f
}


# Create a new stack
createStack() {
  local method="${1:-"create"}"
  outputHeading "Preparing to $method stack..."
  local args=($(buildArgs LANDSCAPE AUTHENTICATION DNS WAF ALB MONGO RDS_SOURCE ADVANCED))
  isDebug && local debug='-x'
  local cmd="sh $debug main.sh $method-stack ${args[@]}"  
  local rootdir="kuali_$(echo $STACK_TYPE | sed 's/-/_/g')"
  local rootpath="$JENKINS_HOME/kuali-infrastructure/$rootdir"
  
  if [ -d "$rootpath" ] ; then
    cd $rootpath
  elif [ -d ./$rootdir ] ; then
    cd $rootdir
  elif isCurrentDir 'KualiUI' ; then
    cd ../../$rootdir
  fi
  echo "Current working directory: $(pwd)"

  echo "$cmd"
  eval "$cmd"
  return $?
}

recreateStack() {
  createStack 'recreate'
}

# Delete an existing stack
deleteStack() {
  outputHeading "Preparing to delete stack..."
  local args=($(buildArgs STACK LANDSCAPE))
  isDebug && local debug='-x'
  local cmd="sh $debug main.sh delete-stack ${args[@]}"
  cd $JENKINS_HOME/kuali-infrastructure/
  # TODO: Users may figure out how to override the default naming conventions for stacks so that the name does not 
  # reflect the stack type. Might be worth replacing the next 7 lines of code with some alternative method of identifying stack type.
  if [ -n "$(echo $STACK | grep -o 'ec2-alb')" ] ; then
    cd kuali_ec2_alb
  elif [ -n "$(echo $STACK | grep -o 'ec2')" ] ; then
    cd kuali_ec2
  else
    cd kuali_ecs
  fi
  echo "$cmd"
  [ "$DRYRUN" == false ] && eval "$cmd"
  return $?
}

runStackAction() {
  case "$STACK_ACTION" in
    create) createStack ;;
    delete) deleteStack ;;
    recreate) recreateStack ;;
    *)
      err "Missing: STACK_ACTION"
      exit 1
      ;;
  esac
}

# Call run with any combination of parse, validate, pull, and run, or no parameters to imply all of them.
run() {
  local task="$1"
  [ -n "$task" ] && shift
  case "$task" in
    parse)
      processParametersQueryString      
      isDebug && set -x
      ;;
    validate)
      validateChoices ;;
    pull)
     pullCodeFromGithub ;;
    run)
      runStackAction ;;
    stop)
      return 0 ;;
    *)
      # run 'parse' 'validate' 'pull' 'run' 'stop' 
      run 'parse' 'validate' 'run' 'stop' 
      return 0 ;;
  esac
  local parms=($@)
  [ ${#parms[@]} -gt 0 ] && run $@
}

checkTestHarness $@ 2> /dev/null || true

isDebug && set -x

run $@

retval=$?
echo "Return code: $retval"

if [ $retval -gt 0 ] ; then
  echo "Failing job..."
  exit 1
else
  echo "Job success"
  exit 0
fi    
