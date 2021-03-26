set +x

outputHeading() {
  local border='*******************************************************************************'
  echo ""
  echo "$border"
  echo "       $1"
  echo "$border"
}
  
err() {
  echo "Error: $*" >>/dev/stderr
}

urldecode() {
  local url_encoded="${1//+/ }"
  printf '%b' "${url_encoded//%/\\x}"
}

# Parameters are all combined into a single querystring. Split them up into separate shell variables.
processParametersQueryString() {
  outputHeading 'Breaking down parameter querystring...'
  PARAMETERS="$(echo "$PARAMETERS" | sed 's/,//g')"
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
  for pair in $(echo "$PARAMETERS" | awk 'BEGIN {RS="&"} {print $1}') ; do
    echo "$pair" && eval "$pair";
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
  if [ -z "$RDS_SOURCE" ] ; then
    err "MISSING: RDS_SOURCE"
    exit 1
  fi
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
      args=(${args[@]} $1)
    fi
  }
  
  for parm in $@ ; do
    case $parm in
      STACK) 
        putArg FULL_STACK_NAME=$STACK ;;
      LANDSCAPE) 
        putArg LANDSCAPE=$LANDSCAPE ;;
      AUTHENTICATION)
        local shib='false'
        [ "${AUTHENTICATION,,}" == 'shibboleth' ] && shib='true'
        putArg USING_SHIBBOLETH=$shib
        ;;
      DNS)
        local route53='false'
        [ "${AUTHENTICATION,,}" == 'route53' ] && route53='true'
        putArg USING_ROUTE53=$shib
        ;;
      WAF)
        putArg CREATE_WAF=$WAF 'false' ;;
      ALB)
        putArg ENABLE_ALB_LOGGING=$ALB 'false' ;;
      MONGO)
        putArg CREATE_MONGO=$MONGO ;;
      RDS_SOURCE)
        putArg RDS_ARN_TO_CLONE=$(urldecode $RDS_INSTANCE_BY_LANDSCAPE) 'false'
        putArg RDS_ARN_TO_CLONE=$(urldecode $RDS_INSTANCE_BY_BASELINE) 'false'
        putArg RDS_SNAPSHOT_ARN=$(urldecode $RDS_SNAPSHOT) 'false'
        ;;
      ADVANCED)
        putArg RETAIN_LAMBDA_CLEANUP_LOGS=$ADVANCED_KEEP_LAMBDA_LOGS 'false'
        if [ -n "$ADVANCED_MANUAL_ENTRIES" ] ; then
          while read line ; do
            local pair=($(echo $line | sed 's/=/ /g'))
            if [ ${#pair[@]} -eq 2 ] ; then
              putArg "$line"
            else
              echo "BAD MANUAL ENTRY - MUST FOLLOW KEY=VALUE"
              exit 1
            fi
          done <<< "$(urldecode $ADVANCED_MANUAL_ENTRIES)"
        fi
        ;;
    esac
  done
  
  [ -z "$DEEP_VALIDATION" ] && putArg DEEP_VALIDATION=false
  [ -z "$PROMPT" ] && putArg PROMPT=false
  [ "$DRYRUN" == true ] && putArg DEBUG=true
  
  echo ${args[@]}
}


pullCodeFromGithub() {
  outputHeading 'Pulling kuali-infrastructure github repository...'
  source $JENKINS_HOME/cli-credentials.sh
  java -jar $JENKINS_HOME/jenkins-cli.jar -s http://localhost:8080/ build fetch-and-reset-kuali-infrastructure -v -f
}


# Create a new stack
createStack() {
  outputHeading "Preparing to create stack..."
  local args=($(buildArgs LANDSCAPE AUTHENTICATION DNS WAF ALB MONGO RDS_SOURCE ADVANCED))
  local cmd="sh main.sh create-stack ${args[@]}"
  cd $JENKINS_HOME/kuali-infrastructure/kuali_$(echo $STACK_TYPE | sed 's/-/_/g')
  echo "$cmd"
  eval "$cmd"
  true
}

# Delete an existing stack
deleteStack() {
  outputHeading "Preparing to delete stack..."
  local args=($(buildArgs STACK))
  local cmd="sh main.sh delete-stack ${args[@]}"
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
  eval "$cmd"
  true
}

runStackAction() {
  case "$STACK_ACTION" in
    create) createStack ;;
    delete) deleteStack ;;
    *)
      err "Missing: STACK_ACTION"
      exit 1
      ;;
  esac
}

# Call run with any combination of parse, validate, pull, and run, or no parameters to imply all of them.
run() {
  local task="$1"
  shift
  case "$task" in
    parse)
      processParametersQueryString ;;
    validate)
      validateChoices ;;
    pull)
     pullCodeFromGithub ;;
    run)
      runStackAction ;;
    stop)
      return 0 ;;
    *)
      run 'parse' 'validate' 'pull' 'run' 'stop' 
      return 0 ;;
  esac
  local parms=($@)
  [ ${#parms[@]} -gt 0 ] && run $@
}

DRYRUN='true'

PARAMETERS=$(echo '
STACK_ACTION=create&
STACK_TYPE=ecs&
AUTHENTICATION=shibboleth&
DNS=route53&
RDS_SOURCE=snapshot&
RDS_INSTANCES_BY_BASELINE=arn%3Aaws%3Ards%3Aus-east-1%3A770203350335%3Adb%3Akuali-oracle-ci&
RDS_SNAPSHOT=arn%3Aaws%3Ards%3Aus-east-1%3A770203350335%3Asnapshot%3Ards%3Akuali-oracle-ci-2021-03-15-22-08&
LANDSCAPE=qa&
WAF=true&
ALB=true&
MONGO=true&
ADVANCED=true&
ADVANCED_KEEP_LAMBDA_LOGS=true&
ADVANCED_MANUAL_ENTRIES=one%3D1%0Atwo%3D2%0Athree%3D3
' | tr -d '\n')

run parse validate 

buildArgs LANDSCAPE AUTHENTICATION DNS WAF ALB MONGO RDS_SOURCE ADVANCED