
checkAwsProfile() {
  if [ -z "$AWS_PROFILE" ] ; then
    while true ; do
      printf "Enter the AWS_PROFILE\n: "
      read AWS_PROFILE
      [ -z "$AWS_PROFILE" ] && echo "EMPTY VALUE! Try again" && continue;
      break;
    done
  fi
  export AWS_PROFILE=$AWS_PROFILE
}

checkTestHarness() {
  if [ -n "$JENKINS_HOME" ] ; then
    echo "Not a local environment - assuming jenkins server..."
  else
    echo "Simulating jenkins environment..."
    if [ -z "$JENKINS_HOME" ] ; then
      JENKINS_HOME=$(dirname "$(pwd)")
    fi
    if [ -z "$DRYRUN" ] ; then
      DRYRUN='true'
    fi
    if [ -z "$PARAMETERS" ] && [ "$DUMMY_PARAMETERS" != 'true' ] ; then
      if [ -n "$PARAMETERS_FILE" ] ; then
        source "$PARAMETERS_FILE"
      else
        echo "ERROR: Running locally and parameters are not set"
        exit 1
      fi
    fi
  fi

  if [ -f ./scripts/common-functions.sh ] ; then
    echo "Sourcing common-functions.sh"
    source ./scripts/common-functions.sh
  else
    echo "Cannot find common-functions.sh"
    exit 1
  fi

  checkAwsProfile
}