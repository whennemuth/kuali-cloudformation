#!/bin/bash

if [ -f ../scripts/common-functions.sh ] ; then
  source ../scripts/common-functions.sh
elif [ -f common-functions.sh ] ; then
  source common-functions.sh
else
  source ../../scripts/common-functions.sh
fi

parseArgs $@

[ -z "$LOCAL_PORT" ] && LOCAL_PORT='5432'
[ -z "$REMOTE_PORT" ] && REMOTE_PORT='1521'
[ -z "$METHOD" ] && METHOD='ssm'
[ -z "$USER_TERMINATED" ] && USER_TERMINATED='true'

tunnelToRDS() {
  if [ -z "$RDS_ENDPOINT" ] ; then
    if [ -n "$LANDSCAPE" ] ; then
      echo "Looking up RDS arn..."
      local arn="$(
        aws resourcegroupstaggingapi get-resources \
          --resource-type-filters rds:db \
          --tag-filters \
              "Key=Environment,Values=$LANDSCAPE" \
              'Key=App,Values=Kuali' \
          --output text \
          --query 'ResourceTagMappingList[0].{ARN:ResourceARN}' 2> /dev/null
      )"
      echo "Looking up RDS endpoint..."
      RDS_ENDPOINT="$(
        aws rds describe-db-instances \
          --db-instance-identifier $arn \
          --output text \
          --query 'DBInstances[0].{Address:Endpoint.Address}' 2> /dev/null
      )"
    else
      echo "WARNING! Landscape parameter is missing for RDS endpoint lookup."
      echo "Cancelling..."
      exit 101
    fi
    if [ -z "$RDS_ENDPOINT" ] ; then
      echo "Lookup for RDS endpoint failed!"
      echo "Cancelling..."
      exit 102
    fi
  fi
  
  if [ -z "$JUMPBOX_INSTANCE_ID" ] ; then
    if [ -n "$LANDSCAPE" ] ; then
      echo "Looking up jumpbox instance ID..."
      instance_state="$(
        aws ec2 describe-instances \
          --filters \
              'Name=tag:App,Values=Kuali' \
              'Name=tag:Type,Values=Jumpbox' \
              "Name=tag:Environment,Values=$LANDSCAPE" \
          --output text \
          --query 'Reservations[].Instances[].{ID:InstanceId,state:State.Name}' | tail -1 2> /dev/null
      )"
    fi
    if [ -z "$instance_state" ] ; then
      echo "INSUFFICIENT PARAMETERS! Jumpbox instance ID is missing"
      echo "Cancelling..."
      exit 103 
    else
      JUMPBOX_INSTANCE_ID="$(echo "$instance_state" | awk '{print $1}')"
      JUMPBOX_INSTANCE_STATE="$(echo "$instance_state" | awk '{print $2}')"
    fi
  fi

  echo "Looking up jumpbox instance data from ID..."
  local data="$(aws \
    ec2 describe-instances \
    --instance-id $JUMPBOX_INSTANCE_ID \
    --output text \
    --query 'Reservations[].Instances[0].{AZ:Placement.AvailabilityZone,ID:PrivateIpAddress}' 2> /dev/null
  )"

  local az=$(echo "$data" | awk '{print $1}' 2> /dev/null)
  if [ -z "$az" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox availability zone is missing and could not be looked up."
    echo "Cancelling..."
    exit 104
  fi

  local region=$(echo "$az" | sed 's/[a-z]$//')
  if [ -z "$region" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox region is missing and could not be looked up."
    echo "Cancelling..."
    exit 105
  fi

  local privateIp=$(echo "$data" | awk '{print $2}')
  if [ -z "$privateIp" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox instance private ip is missing and could not be looked up."
    echo "Cancelling..."
    exit 106
  fi

  if [ "${JUMPBOX_INSTANCE_STATE,,}" == 'stopped' ] ; then
    echo "Jumbox instance is in a stopped state, starting..." 
    aws ec2 start-instances --instance-ids $JUMPBOX_INSTANCE_ID > /dev/null
    echo "Waiting until jumbox is fully initialized..."
    waitForEc2InstanceToFinishStarting $JUMPBOX_INSTANCE_ID
    [ $? -lt 0 ] && exit -1
  fi

  # OpenSSH tunneling args:
  # -L 5432:rds_endpoint:1521 Forward the remote oracle database socket to local port 5432
  # -f sends the ssh command execution to a background process so the tunnel stays open after the command completes
  # -N says not to execute anything remotely. As we are just port forwarding, this is fine.
  cat <<-EOF > $cmdfile
  if [ -n "$AWS_PROFILE" ] ; then
    echo "AWS_PROFILE = $AWS_PROFILE"
  else
    echo "Using default aws profile"
  fi

  echo -e 'y\n' | ssh-keygen -t rsa -f tempkey -N '' >/dev/null 2>&1

  aws ec2-instance-connect send-ssh-public-key \\
    --instance-id $JUMPBOX_INSTANCE_ID \\
    --availability-zone $az \\
    --instance-os-user ec2-user \\
    --ssh-public-key file://./tempkey.pub
    
  # method="\${1,,}"
  # For mac which probably uses bash v3, lowercasing must be done this way:
  method="\$(echo "\$1" |  tr '[:upper:]' '[:lower:]')"

  case "\$method" in
    ssm)
      # Requires no open ports on the jumpbox and no campus subnet access via transit gateway.
      # NOTE: You can substitute $JUMPBOX_INSTANCE_ID for '%h' in the ProxyCommand below.

      echo "Establishing SSH Tunnel: jumpbox host using ssm start-session to access rds endpoint"

      ssh -i tempkey \\
        -Nf -M \\
        -S temp-ssh.sock \\
        -L $LOCAL_PORT:$RDS_ENDPOINT:$REMOTE_PORT \\
        -o "UserKnownHostsFile=/dev/null" \\
        -o "ServerAliveInterval 10" \\
        -o "StrictHostKeyChecking=no" \\
        -o ProxyCommand="aws ssm start-session --target $JUMPBOX_INSTANCE_ID --document AWS-StartSSHSession --parameters portNumber=%p --region=$region" \\
        ec2-user@$JUMPBOX_INSTANCE_ID
      ;;
    ssh)
      # This this also works, but requires that the jumpbox host be in a subnet attached to a transit gateway
      # that links the campus VPN(s) so that access can be established on port 22 open on the jumpbox host.

      echo "Establishing SSH Tunnel: jumpbox host has local port 5432 forwarded to rds endpoint on oracle port"

      ssh -i tempkey \\
        -Nf -L $LOCAL_PORT:$RDS_ENDPOINT:$REMOTE_PORT \\
        -o "UserKnownHostsFile=/dev/null" \\
        -M -S temp-ssh.sock \\
        ec2-user@$privateIp
      ;;
  esac

  if [ "$USER_TERMINATED" == 'true' ] ; then
    read -rsn1 -p "Press any key to close session: "; echo
    ssh -O exit -S temp-ssh.sock *
    rm temp*
  fi
EOF

  if [ "$DEBUG" != 'true' ] ; then
    sh $cmdfile $METHOD
  fi
}

tunnelToRDS
