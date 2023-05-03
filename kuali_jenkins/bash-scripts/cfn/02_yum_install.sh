#!/bin/bash
yum update -y && \
yum install -y \
  https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm \
  git \
  zip \
  unzip \
  sysstat \
  jq \
  vim \
  dos2unix
printf "\n\n"