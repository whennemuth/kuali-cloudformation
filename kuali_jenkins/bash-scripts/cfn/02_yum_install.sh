#!/bin/bash
yum update -y
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
yum install -y git
yum install -y zip unzip
yum install -y sysstat
yum install -y jq
yum install -y vim
yum install -y dos2unix

# Yum updates seem to go on in the background. Make sure they finish by repeatedly checking until confirmed.
# Avoids message: "There are unfinished transactions remaining. You might consider running yum-complete-transaction first to finish them"
counter=1
while true ; do
  if [ $counter -ge 60 ] ; then
    echo 'Incomplete/aborted yum transactions remain after 5 minutes'
    break;
  fi
  echo "$counter: Checking yum activity..."
  retval="$(yum-complete-transaction | grep -i 'No unfinished transactions left')"
  if [ -n "$retval" ] ; then
    echo "All yum updates are complete!"
    break;
  fi
  ((counter++))
  sleep 5
done
printf "\n\n"