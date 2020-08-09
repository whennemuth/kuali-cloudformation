#!/bin/bash

if [ -f ../scripts/common-functions.sh ] ; then
  source ../scripts/common-functions.sh
else
  source ../../scripts/common-functions.sh
fi
 
parseArgs $@

tunnelToRDS() {
  if [ -z "$RDS_ENDPOINT" ] ; then
    echo "INSUFFICIENT PARAMETERS! RDS endpoint is missing."
    echo "Cancelling..."
    exit 1
  elif [ -z "$JUMPBOX_INSTANCE_ID" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox instance ID is missing"
    echo "Cancelling..."
    exit 1 
  else
    local data="$(aws \
      ec2 describe-instances \
      --instance-id $JUMPBOX_INSTANCE_ID \
      --output text \
      --query 'Reservations[].Instances[0].{AZ:Placement.AvailabilityZone,ID:PrivateIpAddress}' 2> /dev/null
    )"
  fi

  local az=$(echo "$data" | awk '{print $1}' 2> /dev/null)
  if [ -z "$az" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox availability zone is missing and could not be looked up."
    echo "Cancelling..."
    exit 1
  fi

  local region=$(echo "$az" | sed 's/[a-z]$//')
  if [ -z "$region" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox region is missing and could not be looked up."
    echo "Cancelling..."
    exit 1
  fi

  local privateIp=$(echo "$data" | awk '{print $2}')
  if [ -z "$privateIp" ] ; then
    echo "INSUFFICIENT PARAMETERS! Jumpbox instance private ip is missing and could not be looked up."
    echo "Cancelling..."
    exit 1
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

  aws --profile=infnprd ec2-instance-connect send-ssh-public-key \\
    --instance-id $JUMPBOX_INSTANCE_ID \\
    --availability-zone $az \\
    --instance-os-user ec2-user \\
    --ssh-public-key file://./tempkey.pub
    
  method="\${1,,}"

  case "\$method" in
    ssm)
      # Requires no open ports on the jumpbox and no campus subnet access via transit gateway.
      # NOTE: You can substitute $JUMPBOX_INSTANCE_ID for '%h' in the ProxyCommand below.

      echo "Establishing SSH Tunnel: jumpbox host using ssm start-session to access rds endpoint"

      ssh -i tempkey \\
        -Nf -M \\
        -M -S temp-ssh.sock \\
        -L 5432:$RDS_ENDPOINT:1521 \\
        -o "UserKnownHostsFile=/dev/null" \\
        -o "StrictHostKeyChecking=no" \\
        -o ProxyCommand="aws --profile infnprd ssm start-session --target $JUMPBOX_INSTANCE_ID --document AWS-StartSSHSession --parameters portNumber=%p --region=$region" \\
        ec2-user@$JUMPBOX_INSTANCE_ID
      ;;
    ssh)
      # This this also works, but requires that the jumpbox host be in a subnet attached to a transit gateway
      # that links the campus VPN(s) so that access can be established on port 22 open on the jumpbox host.

      echo "Establishing SSH Tunnel: jumpbox host has local port 5432 forwarded to rds endpoint on oracle port"

      ssh -i tempkey \\
        -Nf -L 5432:$RDS_ENDPOINT:1521 \\
        -M -S temp-ssh.sock \\
        ec2-user@$privateIp
      ;;
  esac

  read -rsn1 -p "Press any key to close session: "; echo
  ssh -O exit -S temp-ssh.sock *
  rm temp*
EOF

  if [ "$DEBUG" != 'true' ] ; then
    sh $cmdfile ssm
  fi
}

tunnelToRDS
