#!/bin/bash

if [ -d "$BASE_DIR" ] ; then
  source $BASE_DIR/scripts/common-functions.sh
elif [ -f scripts/common-functions.sh ] ; then
  source scripts/common-functions.sh
elif [ -f ./common-functions.sh ] ; then
  source ./common-functions.sh
else
  echo "ERROR! Cannot find common-functions.sh"
  exit 1
fi

visitEC2() {
  [ ! -f ec2-instance-id ] && return 0
  local instanceId=$(cat ec2-instance-id)
  rm -f ec2-instance-id
  if [ -n "$instanceId" ] && [ "${instanceId,,}" != 'cancel' ] ; then
    local cmd="aws ssm start-session --target $instanceId"
    [ -n "$(winpty --version 2> /dev/null)" ] && cmd="winpty $cmd"
    echo "$cmd"
    isDryrun && return 0
    eval "$cmd"
  else
    echo "Could not find running ec2 instance(s) that match!"
    [ -z "$AWS_PROFILE" ] && ([ "$PROFILE" == 'default' ] || [ -z "$PROFILE" ]) && "Did you forget to pass in an aws profile argument?"
  fi
}

task=$1 && shift

parseArgs $@

filters=(
  'Key=Function,Values='${kualiTags['Function']}
  'Key=Service,Values='${kualiTags['Service']}
)
[ -n "$LANDSCAPE" ] && filters=(${filters[@]} "Key=Landscape,Values=$LANDSCAPE")

case "${task,,}" in
  jenkins)
    filters=(${filters[@]} "Key=ShortName,Values=jenkins")
    ;;
  app)
    filters=('nameFragment=ec2' ${filters[@]})
    ;;
  mongo)
    filters=('nameFragment=mongo' ${filters[@]})
    ;;
  any)
    ;;
  *)
    echo 'Unknown task! (use "jenkins", "app", "mongo", or "any")'
    exit 1
    ;;
esac

echo "pickEC2InstanceId ${filters[@]}"

pickEC2InstanceId ${filters[@]}

visitEC2 
