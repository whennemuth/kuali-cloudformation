#!/bin/bash

cmdfile=last-cmd.sh

parseArgs() {
  for nv in $@ ; do
    name="$(echo $nv | cut -d'=' -f1)"
    value="$(echo $nv | cut -d'=' -f2-)"
    echo "${name^^}=$value"
    eval "${name^^}=$value" 2> /dev/null || true
  done
}

setGeneralDefaults() {
  tempath="$(dirname "$TEMPLATE")"
  if [ "$tempath" != "." ] ; then
    TEMPLATE_PATH=$tempath
    # Strip off the directory path and reduce down to file name only.
    TEMPLATE=$(echo "$TEMPLATE" | grep -oP '[^/]+$')
  fi

  # Trim off any trailing forward slashes
  TEMPLATE_PATH=$(echo "$TEMPLATE_PATH" | sed 's/\/*$//')
  # Get the http location of the bucket path 
  BUCKET_URL="$(echo "$BUCKET_PATH" | sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//')"
  # Fish out just the bucket name from the larger bucket path
  BUCKET_NAME="$(echo "$BUCKET_PATH" | grep -oP '(?<=s3://)([^/]+)')"
}

# Validate one or all cloudformation yaml templates.
validateStack() {
  local silent="$1"
  local root=$(pwd)
    
  cd $TEMPLATE_PATH
  rm -f $root/validate.valid 2> /dev/null
  rm -f $root/validate.invalid 2> /dev/null
  find . -type f -iname "*.yaml" | \
  while read line; do \
    local f=$(printf "$line" | sed 's/^.\///'); \
    [ -n "$TEMPLATE" ] && [ "$TEMPLATE" != "$f" ] && continue;
    printf "validating $f";

    validate "$f" >> $root/validate.valid 2>> $root/validate.invalid
    if [ $? -gt 0 ] ; then
      echo $f >> $root/validate.invalid
    fi
    echo " "
  done
  cd $root
  if [ -z "$silent" ] ; then
    cat $root/validate.valid
  fi
  if [ -f $root/validate.invalid ] && [ -n "$(cat $root/validate.invalid)" ]; then
    cat $root/validate.invalid
    rm -f $root/validate.invalid 2> /dev/null
    rm -f $root/validate.valid 2> /dev/null
    exit 1
  else
    rm -f $root/validate.invalid 2> /dev/null
    rm -f $root/validate.valid 2> /dev/null
    echo "SUCCESS! (no errors found)"
  fi
}

# Validate a single cloudformation yaml file
validate() {
  local template="$1"
  printf "\n\n$template:" && \
  aws cloudformation validate-template --template-body "file://./$template"
}

# Upload one or all cloudformation yaml templates to s3
uploadStack() {
  validateStack silent

  [ $? -gt 0 ] && exit 1

  if [ -n "$TEMPLATE" ] ; then
    if [ -f $TEMPLATE ] ; then
      echo "aws s3 cp $TEMPLATE $BUCKET_PATH" > $cmdfile
    elif [ -f $TEMPLATE_PATH/$TEMPLATE ] ; then
      echo "aws s3 cp $TEMPLATE_PATH/$TEMPLATE $BUCKET_PATH" > $cmdfile
    else
      echo "$TEMPLATE not found!"
      exit 1
    fi
  else
    cat <<-EOF > $cmdfile
    aws s3 cp $TEMPLATE_PATH $BUCKET_PATH \\
      --exclude=* \\
      --include=*.yaml \\
      --recursive
EOF
  fi

  if [ "$DEBUG" ] ; then
    cat $cmdfile
    return 0
  fi
  
  # Create an s3 bucket for the app if it doesn't already exist
  if [ -z "$(aws s3 ls $BUCKET_NAME 2> /dev/null)" ] ; then
    aws s3 mb s3://$BUCKET_NAME
  fi

  printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  read answer
  # local answer="y"
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."
}

# Add on key=value entry to the construction of an aws cli function call to 
# perform a create/update stack action.
addParameter() {
  local cmdfile="$1"
  local key="$2"
  local value="$3"
  [ -n "$(cat $cmdfile | grep 'ParameterKey')" ] && local comma=","
  cat <<-EOF >> $cmdfile
        ${comma}{
          "ParameterKey" : "$key",
          "ParameterValue" : "$value"
        }
EOF
}

# Issue an ssm command to an ec2 instance to re-run its init functionality from it's metadata.
metaRefresh() {
  getInstanceId() (
    aws cloudformation describe-stack-resources \
      --stack-name $STACK_NAME \
      --logical-resource-id $LOGICAL_RESOURCE_ID \
      | jq '.StackResources[0].PhysicalResourceId' \
      | sed 's/"//g'
  )

  local instanceId="$(getInstanceId)"
  
  if [ -z "$instanceId" ] ; then
    echo "ERROR! Cannot determine instanceId in stack \"$STACK_NAME\""
    exit 1
  else
    echo "instanceId = $instanceId"
  fi

  printf "Enter the name of the configset to run: "
  read configset
  # NOTE: The following does not seem to work properly:
  #       --parameters commands="/opt/aws/bin/cfn-init -v --configsets $configset --region "us-east-1" --stack "ECS-EC2-test" --resource $LOGICAL_RESOURCE_ID"
  # Could be a windows thing, or could be a complexity of using bash to execute python over through SSM.
	cat <<-EOF > $cmdfile
	aws ssm send-command \\
		--instance-ids "${instanceId}" \\
		--document-name "AWS-RunShellScript" \\
		--comment "Implementing cloud formation metadata changes on ec2 instance $LOGICAL_RESOURCE_ID ($instanceId)" \\
		--parameters \\
		'{"commands":["/opt/aws/bin/cfn-init -v --configsets '"$configset"' --region \"us-east-1\" --stack \"$STACK_NAME\" --resource $LOGICAL_RESOURCE_ID"]}'
	EOF

  if [ "$DEBUG" ] ; then
    cat $cmdfile
    exit 0
  fi

  printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  read answer
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."
}


# Create a public/private keypair
createEc2KeyPair() {
  local keyname="$1"
  local cleanup="$2"
  # Create an s3 bucket for the app if it doesn't already exist
  if [ -z "$(aws s3 ls $BUCKET_NAME 2> /dev/null)" ] ; then
    aws s3 mb s3://$BUCKET_NAME
  fi
  # Generate the keypair
  ssh-keygen -b 2048 -t rsa -f $keyname -q -N ""

  # Import the keypair to aws ec2 keypairs
  if [ -n "$(aws ec2 import-key-pair help | grep 'tag-specifications')" ] ; then
    local tagspec="--tag-specifications 'ResourceType=key-pair,Tags=[{Key=Name,Value='$keyname'}]'"
  else
    echo "You're using an older version of the aws cli - imported keypair will have no tags"
  fi
  aws ec2 describe-key-pairs --key-names $keyname 2> /dev/null
  if [ $? -eq 0 ] ; then
    echo "$keyname already exists upstream, deleting..."
    aws ec2 delete-key-pair --key-name $keyname
  fi

  echo "Importing $keyname ..."
  aws ec2 import-key-pair \
    --key-name "$keyname" \
    $tagspec \
    --public-key-material file://./$keyname.pub
    
  # Upload the private key to the s3 bucket
  aws s3 cp ./$keyname s3://$BUCKET_NAME/
  # Remove the keypair locally
  if [ -n "$cleanup" ] ; then
    rm -f $keyname && rm -f $keyname.pub
  else
    chmod 600 $keyname
  fi
}