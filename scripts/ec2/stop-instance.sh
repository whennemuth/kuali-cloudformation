#!/bin/bash

# Target this script with a crontab and the instance will be shutdown on the crontab schedule if tagging indicates it's authorized.
local region="$1"
[ -z "$region" ] && echo "No region specified. Ec2 shutdown Cancelled." && exit 0
instanceId=$(curl http://169.254.169.254/latest/meta-data/instance-id 2> /dev/null)
stoppable=$(aws ec2 describe-tags \
  --filters \
    "Name=resource-id,Values=$instanceId" \
    "Name=key,Values=self-stoppable" \
  --region $region \
  --output=text | cut -f5 2> /dev/null
)
if [ "$stoppable" != 'true' ] ; then
  exit 0
fi
# You can skip the next scheduled shutdown by creating a /tmp/skipshutdown file.
if [ -f /tmp/skipshutdown ] ; then
  echo "$(date) Skipping shutdown for today - skip file found." >>  /usr/local/sbin/cronlog
  rm -f /tmp/skipshutdown
  exit 0
fi

echo "$(date) Stopping instance per cron schedule..." >> /usr/local/sbin/cronlog
aws ec2 stop-instances --region $region --instance-ids $instanceId >> /usr/local/sbin/cronlog 2>&1
