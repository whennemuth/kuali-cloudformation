#!/bin/bash

run() {
  if [ "$(pwd | grep -oP '[^/]+$')" != "kuali_ec2" ] ; then
    echo "You must run this script from the kuali_ec2 subdirectory!."
    exit 1
  fi

  source ../scripts/common-functions.sh

  task="${1,,}"
  shift

  parseArgs $@

  setCustomDefaults

  setGeneralDefaults

  runTask
}

setCustomDefaults() {
  # GLOBAL_TAG
  # TEMPLATE
  # EC2_INSTANCE_TYPE
  # LOGICAL_RESOURCE_ID
  [ -z "$STACK_NAME" ] && STACK_NAME='kuali-ec2'
  [ -z "$LANDSCAPE" ] && LANDSCAPE='sb'
  [ -z "$BUCKET_PATH" ] && BUCKET_PATH='s3://kuali-research-ec2-setup/cloudformation/kuali_ec2'
  [ -z "$CONFIG_BUCKET" ] && CONFIG_BUCKET='kuali-research-ec2-setup'
  [ -z "$TEMPLATE_PATH" ] && TEMPLATE_PATH='.'
  [ -z "$KC_IMAGE" ] && KC_IMAGE='730096353738.dkr.ecr.us-east-1.amazonaws.com/coeus-sandbox:2001.0040'
  [ -z "$CORE_IMAGE" ] && CORE_IMAGE='730096353738.dkr.ecr.us-east-1.amazonaws.com/core:2001.0040'
  [ -z "$PORTAL_IMAGE" ] && PORTAL_IMAGE='730096353738.dkr.ecr.us-east-1.amazonaws.com/portal:2001.0040'
  [ -z "$PDF_IMAGE" ] && PDF_IMAGE='730096353738.dkr.ecr.us-east-1.amazonaws.com/research-pdf:2002.0003'
}

# Create, update, or delete the cloudformation stack for course schedule planner.
stackAction() {  
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $STACK_NAME
    
    [ $? -gt 0 ] && echo "Cancelling..." && return 1
  else
    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    # If creating the stack, create and import a keypair to configure the ec2 instance with for shell access.
    if [ "$action" == 'create-stack' ] ; then
      local keypairName="kuali-ec2-$LANDSCAPE-keypair"
      createEc2KeyPair $keypairName
      chmod 600 $keypairName
    fi

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name $STACK_NAME \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      --template-url $BUCKET_URL/ec2.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'ConfigBucket' $CONFIG_BUCKET
    addParameter $cmdfile 'KcImage' $KC_IMAGE
    addParameter $cmdfile 'CoreImage' $CORE_IMAGE
    addParameter $cmdfile 'PortalImage' $PORTAL_IMAGE
    addParameter $cmdfile 'PdfImage' $PDF_IMAGE
    [ -n "$LANDSCAPE" ] && \
      addParameter $cmdfile 'Landscape' $LANDSCAPE
    [ -n "$GLOBAL_TAG" ] && \
      addParameter $cmdfile 'GlobalTag' $GLOBAL_TAG
    [ -n "$EC2_INSTANCE_TYPE" ] && \
      addParameter $cmdfile 'EC2InstanceType' $EC2_INSTANCE_TYPE
    [ -n "$ENABLE_NEWRELIC_APM" ] && \
      addParameter $cmdfile 'EnableNewRelicAPM' $ENABLE_NEWRELIC_APM
    [ -n "$ENABLE_NEWRELIC_INFRASTRUCTURE" ] && \
      addParameter $cmdfile 'EnableNewRelicInfrastructure' $ENABLE_NEWRELIC_INFRASTRUCTURE
    [ -n "$keypairName" ] && \
      addParameter $cmdfile 'EC2KeypairName' $keypairName

    echo "      ]'" >> $cmdfile

    if [ "$DEBUG" ] ; then
      cat $cmdfile
      exit 0
    fi

    printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
    read answer
    [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."

    [ $? -gt 0 ] && echo "Cancelling..." && return 1
  fi
}

runTask() {
  case "$task" in
    validate)
      validateStack ;;
    upload)
      uploadStack ;;
    create-stack)
      stackAction "create-stack" ;;
    update-stack)
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
    refresh)
      metaRefresh ;;
    examples)
      examples ;;
    *)
      if [ -n "$task" ] ; then
        echo "INVALID PARAMETER: No such task: $task"
      else
        echo "MISSING PARAMETER: task"
      fi
      exit 1
      ;;
  esac
}

run $@