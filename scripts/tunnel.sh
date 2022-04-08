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
      "app", "mongo", "jenkins", "jvm-agent" "any"
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
    or...
    sh tunnel.sh jvm-agent landscape=stg
EOF
  exit 1
}

tunnelMethodSSM() {
  aws ssm start-session \
    --target $EC2_INSTANCE_ID \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["'$REMOTE_PORT'"],"localPortNumber":["'$LOCAL_PORT'"]}'
}

tunnelMethodSSH() {
  local ip="$(getEc2InstanceIp "$EC2_INSTANCE_ID" 'retain')"
  local az="$(getEc2InstanceAZ "$EC2_INSTANCE_ID")"
  
  cat <<EOF > $cmdfile
  [ -f tempkey ] && rm -f tempkey
  [ -f tempkey.pub ] && rm -f tempkey.pub
  echo -e 'y\n' | ssh-keygen -t rsa -f tempkey -N '' -C '' >/dev/null 2>&1

  echo "Sending ssh key..."
  aws ec2-instance-connect send-ssh-public-key \\
    --instance-id $EC2_INSTANCE_ID \\
    --availability-zone $az \\
    --instance-os-user ec2-user \\
    --ssh-public-key file://./tempkey.pub

  echo "Starting ssh port forwarding..."
  # ssh -i ~/.ssh/buaws-kuali-rsa -N -v -L 9229:10.57.242.100:9229 wrh@10.57.242.100
  
  # ssh -i tempkey \\
  #   -Nf -L $LOCAL_PORT:$ip:$REMOTE_PORT \\
  #   -o "UserKnownHostsFile=/dev/null" \\
  #   -M -S temp-ssh.sock \\
  #   ec2-user@$ip
  
  ssh -i tempkey \\
    -N -v -L $LOCAL_PORT:$ip:$REMOTE_PORT \\
    -o "UserKnownHostsFile=/dev/null" \\
    ec2-user@$ip
EOF

echo "$(pwd)/${cmdfile}:"
cat $cmdfile
# sh $cmdfile
}

tunnelEC2() {
  if [ -z "$EC2_INSTANCE_ID" ] ; then
    [ ! -f ec2-instance-id ] && return 0
    EC2_INSTANCE_ID=$(cat ec2-instance-id)
    rm -f ec2-instance-id
    if [ -n "$EC2_INSTANCE_ID" ] && [ "${EC2_INSTANCE_ID,,}" != 'cancel' ] ; then
      if [ "${task,,}" == 'jvm-agent' ] ; then
        tunnelMethodSSH
      else
        tunnelMethodSSM
      fi
    fi
  else
    echo "Could not find running ec2 instance(s) that match!"
    [ -z "$AWS_PROFILE" ] && ([ "$PROFILE" == 'default' ] || [ -z "$PROFILE" ]) && "Did you forget to pass in an aws profile argument?"
  fi
}

setFilters() {
  filters=(
    'Key=Function,Values='${kualiTags['Function']}
    'Key=Service,Values='${kualiTags['Service']}
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
    jvm-agent)
      [ -z "$LOCAL_PORT" ] && LOCAL_PORT=8787
      [ -z "$REMOTE_PORT" ] && REMOTE_PORT=8787
      if [ -n "$LANDSCAPE" ] ; then
        filters=(${filters[@]} "Key=Landscape,Values=$LANDSCAPE")
      fi
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
