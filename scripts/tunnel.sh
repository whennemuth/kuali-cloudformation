#!/bin/bash

# Use this script to start a port forwarding session to an ec2 instance and forward activity on a remote port to a local port.
# The purpose of this would be connect to remote services typically residing in private LAN by tunneling around a network gateway, 
# such as a router or firewall.
# For example, you could forward traffic from a remote port 80 handled by a web server on a private ec2 instance to port 8080 
# on your laptop. You could then access the default web page of web server in your browser at: http://localhost:8080/

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

printUsage() {
  cat <<EOF

USAGE:
  sh tunnel.sh task profile=? local_port=? remote_port=?
  task: What function does the ec2 instance being tunnelled perform? 
    Possible values: [
      "app", "mongo", "jenkins", "any"
    ]
  and...
  local_port: The port being forwarded to - your local port.
  and...
  remote_port: The port being forwarded from - the port at the target end inside the ec2 instance.
  and... 
  [ 
    ec2_instance_id: The instance id of the ec2 instance you want to tunnel into.
    or (optionally)...
    landcape: The ec2 instance you want to tunnel into will have a landscape tag (ie: qa, stg, etc.)
              Enter the value of that tag.
  ]

  Example:
    sh tunnel.sh jenkins local_port=8080 remote_port=80 ec2_instance=i-058786b59998fba38
    or...
    sh tunnel.sh jenkins local_port=8080 remote_port=80 landscape=qa
EOF
  exit 1
}

tunnelEC2() {
  if [ -z "$EC2_INSTANCE_ID" ] ; then
    [ ! -f ec2-instance-id ] && return 0
    EC2_INSTANCE_ID=$(cat ec2-instance-id)
    rm -f ec2-instance-id
  fi
  if [ -n "$EC2_INSTANCE_ID" ] && [ "${EC2_INSTANCE_ID,,}" != 'cancel' ] ; then
    aws ssm start-session \
      --target $EC2_INSTANCE_ID \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["'$REMOTE_PORT'"],"localPortNumber":["'$LOCAL_PORT'"]}'
  else
    echo "Could not find running ec2 instance(s) that match!"
    [ "$PROFILE" == 'default' ] && "Did you forget to pass in an aws profile argument?"
  fi
}

setFilters() {
  filters=(
    'Key=Function,Values=kuali'
    'Key=Service,Values=research-administration'
  )
  [ -n "$landscape" ] && filters=(${filters[@]} "Key=Landscape,Values=$landscape")

  case "${task,,}" in
    jenkins)
      filters=(${filters[@]} "Key=Name,Values=kuali-jenkins")
      ;;
    app)
      filters=('nameFragment=ec2' ${filters[@]})
      ;;
    mongo)
      [ -z "$LOCAL_PORT" ] && LOCAL_PORT=27017
      [ -z "$REMOTE_PORT" ] && REMOTE_PORT=27017
      filters=('nameFragment=mongo' ${filters[@]})
      ;;
    any)
      ;;
    *)
      echo 'Unknown task! (use "jenkins", "app", "mongo", or "any")'
      exit 1
      ;;
  esac

  if ! isNumeric "$LOCAL_PORT" ; then printUsage; fi
  if ! isNumeric "$REMOTE_PORT" ; then printUsage; fi
  # [ -z "$EC2_INSTANCE_ID" ] && [ -z "$LANDSCAPE" ] && printUsage
}

task=$1 && shift

parseArgs $@

setFilters

pickEC2InstanceId ${filters[@]}

tunnelEC2 
