#!/bin/bash

# Use this script to start a port forwarding session to an ec2 instance and forward activity on a remote port to a local port.
# The purpose of this would be connect to remote services typically residing in private LAN by tunneling around a network gateway, 
# such as a router or firewall.
# For example, you could forward traffic from a remote port 80 handled by a web server on a private ec2 instance to port 8080 
# on your laptop. You could then access the default web page of web server in your browser at: http://localhost:8080/

source ../common-functions.sh

parseArgs $@

printUsage() {
  cat <<EOF

USAGE: 
  local_port: The port being forwarded to - your local port.
  and...
  remote_port: The port being forwarded from - the port at the target end inside the ec2 instance.
  and... 
  [ 
    ec2_instance_id: The instance id of the ec2 instance you want to tunnel into.
    or...
    landcape: The ec2 instance you want to tunnel into will have a landscape tag (ie: qa, stg, etc.)
              Enter the value of that tag.
  ]

  Example:
    sh tunnel.sh local_port=8080 remote_port=80 ec2_instance=i-058786b59998fba38
    or...
    sh tunnel.sh local_port=8080 remote_port=80 landscape=qa
EOF
  exit 1
}

if ! isNumeric "$LOCAL_PORT" ; then printUsage; fi
if ! isNumeric "$REMOTE_PORT" ; then printUsage; fi

if [ -z "$EC2_INSTANCE_ID" ] ; then
  [ -z "$LANDSCAPE" ] && printUsage
  echo "Looking up InstanceId for kuali ec2 instance tagged with $LANDSCAPE landscape..."
  arns=(
    $(aws resourcegroupstaggingapi get-resources \
      --resource-type-filters ec2:instance \
      --tag-filters "Key=Landscape,Values=$LANDSCAPE" 'Key=Service,Values=research-administration' 'Key=Function,Values=kuali' \
      --output text \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null
    )
  )

  [ ${#arns[@]} -eq 0 ] && "ERROR! No ec2 can be found for the kuali service with a $LANDSCAPE landscape" && exit 1

  # for line in ${arns[@]} ; do
  #   echo $line
  #   line=$(echo "$line" | grep -oP '[^\s]*')
  #   choices="$choices $line"
  # done
  # echo $choices

  if [ ${#arns[@]} -gt 1 ] ; then
    select choice in $(echo ${arns[@]} | grep -oP '[^\s]*') ; do 
      if isNumeric $REPLY ; then
        if [ $REPLY -ge 1 ] && [ $REPLY -le ${#arns[@]} ] ; then
          arn="$choice"
          break;
        fi
      fi
      echo "Invalid selection - pick 1 to ${#arns[@]}"
    done;
  else
    arn=${arns[0]}
  fi

  EC2_INSTANCE_ID=$(echo $arn | cut -d'/' -f2)  
fi

echo "AWS_PROFILE = $AWS_PROFILE"
echo "Tunneling to $EC2_INSTANCE_ID..."

aws ssm start-session \
  --target $EC2_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["'$REMOTE_PORT'"],"localPortNumber":["'$LOCAL_PORT'"]}'
