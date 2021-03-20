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

# Parameters are all combined into a single querystring. Split them up into separate shell variables.
processParametersQueryString() {
  outputHeading 'Breaking down parameter querystring...'
  PARAMETERS="$(echo "$PARAMETERS" | sed 's/,//g')"
  if [ -z "$PARAMETERS" ] ; then
    echo "No Parameters!"
    exit 1
  else 
    echo "PARAMETERS: $PARAMETERS"
  fi
  
  # Load the querystring into variables.
  for pair in $(echo "$PARAMETERS" | awk 'BEGIN {RS="&"} {print $1}') ; do
    echo "$pair" && eval "$pair";
  done
}

validateChoices() {
  outputHeading 'Validating parameter choices...'
  [ -z "$STACK_ACTION" ] && echo "MISSING STACK_ACTION!" && exit 1
  [ "$STACK_ACTION" == 'create' ] && [ -z "$STACK_TYPE" ] && echo "MISSING STACK_TYPE!" && exit 1
  echo "Parameter choices ok."
}

# Build the arguments to be passed to the stack creation/deletion function call in the main script pulled from git
buildArgs() {
  local args=()
  
  putArg() {
    local name="$(echo "$1" | cut -d'=' -f1)"
    local value="$(echo "$1" | cut -d'=' -f2)"
    if [ -z "$value" ] ; then
      err "Missing parameter value!: $name"
      exit 1
    fi
    args=(${args[@]} $1)
  }
  
  for parm in $@ ; do
    case $parm in
      STACK) 
        putArg FULL_STACK_NAME=$STACK ;;
      BASELINE) 
        putArg BASELINE=$BASELINE ;;
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
        putArg CREATE_WAF=$WAF ;;
      ALB)
        putArg ENABLE_ALB_LOGGING=$ALB ;;
      MONGO)
        putArg CREATE_MONGO=$MONGO ;;
      RDS_CLONE_LANDSCAPE)
        if [ "${RDS_CLONE_LANDSCAPE,,}" != 'none' ] ; then
          if [ "${RDS_SNAPSHOT,,}" != 'none' ] ; then
            putArg RDS_SNAPSHOT_ARN=$RDS_SNAPSHOT
          else
            putArg RDS_ARN_TO_CLONE=$RDS_CLONE_LANDSCAPE
          fi
        fi
        ;;
    esac
  done
  
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
  local args=($(buildArgs BASELINE LANDSCAPE AUTHENTICATION DNS WAF ALB MONGO RDS_CLONE_LANDSCAPE))
  local cmd="sh main.sh create-stack ${args[@]}"
  echo "$cmd"
  cd $JENKINS_HOME/kuali-infrastructure/$(echo $STACK_TYPE | sed 's/-/_/g')
  [ "$DEBUG" == false ] && eval "$cmd"
}

# Delete an existing stack
deleteStack() {
  outputHeading "Preparing to delete stack..."
  local args=($(buildArgs STACK))
  local cmd="sh main.sh delete-stack ${args[@]}"
  echo "$cmd"
  #cd $JENKINS_HOME/kuali-infrastructure/
  # TODO: It's possible to override the default naming conventions for stacks so that the name does not 
  # reflect the stack type. Need to change the next 7 lines of code to something more solid.
  if [ -n "$(echo $STACK | grep -o 'ec2-alb')" ] ; then
    cd kuali_ec2_alb
  elif [ -n "$(echo $STACK | grep -o 'ec2')" ] ; then
    cd kuali_ec2
  else
    cd kuali_ecs
  fi
  [ "$DRYRUN" == false ] && eval "$cmd"
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

JENKINS_HOME=$(dirname "$(pwd)")
DRYRUN=true
PARAMETERS='STACK=kuali-ecs-warrentest1&STACK_ACTION=delete'

processParametersQueryString

validateChoices

# pullCodeFromGithub

runStackAction


