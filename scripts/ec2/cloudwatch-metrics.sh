#!/bin/bash

# Adding additional cloudwatch metrics that include memory utilization.
# See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/mon-scripts.html
sendCustomMetrics1() {
  /var/lib/aws-scripts-mon/mon-put-instance-data.pl \
    --mem-used-incl-cache-buff \
    --mem-util \
    --mem-avail \
    --disk-space-util \
    --disk-path=/ \
    --from-cron
}


# Cloudwatch metrics alternative that include are custom and cover all needed measurments.
# Use this method as a replacement for the mon-put-instance-data.pl approach.
# See: https://aws.amazon.com/premiumsupport/knowledge-center/cloudwatch-custom-metrics/
sendCustomMetrics2() {
  local service="${1^^}"
  export AWS_DEFAULT_REGION=us-east-1
  INSTANCEID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  USEDMEMORY_PERCENT=$(free -m | awk 'NR==2{printf "%.2f\t", $3*100/$2 }')
  USEDDISK_PERCENT=$(df / | awk 'NR==2{print $5}' | sed 's/\%//g')
  TCP_CONN=$(netstat -an | wc -l)
  TCP_CONN_PORT_80=$(netstat -an | grep 80 | wc -l)
  USERS=$(uptime | awk '{ print $4 }')
  IO_WAIT_PERCENT=$(iostat | awk 'NR==4 {print $4}')
  # If no average cpu record, then take the cpu as of this moment
  if [ -z "$(cat /tmp/average.cpu | grep -P '^\d+(\.\d+)?$' 2> /dev/null)" ] ; then
    grep 'cpu ' /proc/stat | awk '{print ($2+$4)*100/($2+$4+$5)}' > /tmp/average.cpu
  fi
  AVERAGE_CPU=$(cat /tmp/average.cpu)
  # Compute the average cpu utilization by taking a reading every 2 seconds for 58 seconds and taking their average.
  # The cron job is on a minute schedule, so 58 seconds will ensure that a new average will be recorded BEFORE the next cron cycle.
  NEXT_AVERAGE_CPU=$(n=0 && cat <(echo "$(while [ $n -lt 4 ] ; do grep 'cpu ' /proc/stat && sleep 2 && n=$((n+1)) ; done)") | awk '{c++; t += ($2+$4)*100/($2+$4+$5)} END {print t/c}')
  echo $NEXT_AVERAGE_CPU > /tmp/average.cpu
  
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}TestCustomMetrics" --metric-name cpu-usage --value $AVERAGE_CPU
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name memory-usage --value $USEDMEMORY_PERCENT
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name disk-usage --value $USEDDISK_PERCENT
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name tcp_connections --value $TCP_CONN
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name tcp_connection_on_port_80 --value $TCP_CONN_PORT_80
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name nbr_of_users --value $USERS
  aws cloudwatch put-metric-data --dimensions Instance=$INSTANCEID --namespace "${Service}EC2TestCustomMetrics" --metric-name io_wait --value $IO_WAIT_PERCENT
}


# This function streams a json file from s3 that indicates dummy metrics to send to cloudwatch.
# The purpose is to simulate higher (or lower) thresholds that would trigger alarms to engage
# a scale-in or scale-out policy for auto-scaling activity.
sendPsuedoMetrics() {
  # local json=$(cat /c/whennemuth/workspaces/ecs_workspace/dummy-metrics/dummy-ec2-metrics.json)
  local service="${1,,}"
  local bucketName="$2"
  local region="$3"
  local json=$(aws s3 cp s3://$bucketName/dummydata/dummy-$service-metrics.json)
  local namespace=$(echo "$json" | jq -r '.Namespace')
  local instances=$(echo $json | jq -r -c '.Instances[]')
  local evals=()
  while read -r instance; do
    local instanceId=$(echo "$instance" | jq -r '.InstanceId')
    local metrics=$(echo $instance | jq -r -c '.Metrics[]')
    while read -r metric; do
      local name=$(echo "$metric" | jq -r '.MetricName')
      local baseline=$(echo "$metric" | jq -r '.BaselineValue')
      local deviation=$(echo "$metric" | jq -r '.DeviationValue')
      # Examples to set until to a value offset from current UTC time
      # date +%s --date='+5 minute'
      # date +%s --date='-1 hour'
      local until=$(echo "$metric" | jq -r '.DeviateUntil')
      local value=$baseline
      local now=$(date +%s)
      [ $until -gt $now ] && value=$deviation
      local evalstr="$(cat <<EOF
        aws cloudwatch put-metric-data \
          --region ${region} \
          --dimensions Instance=$instanceId \
          --namespace "$namespace" \
          --metric-name $name \
          --value $value
EOF
      )"
      evals=("${!evals[@]}" "$(echo "$evalstr" | sed -E 's/[[:space:]]+/ /g' | xargs)")
    done <<< "$metrics"
  done <<< "$instances"

  for cmd in "${!evals[@]}" ; do
    echo "$cmd"
    eval "$cmd"
  done
}


task="${1,,}"
shift

case "$task" in
  custom1)
    sendCustomMetrics1 $@ ;;
  custom2)
    sendCustomMetrics2 $@ ;;
  psuedo)
    sendPsuedoMetrics $@ ;;
esac