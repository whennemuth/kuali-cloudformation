#!/bin/bash
yum update -y
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
yum install -y git
yum install -y zip unzip
yum install -y sysstat
yum install -y jq
yum install -y vim
printf "\n\n"
