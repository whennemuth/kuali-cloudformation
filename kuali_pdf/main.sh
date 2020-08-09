#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-pdf-s3'
  [GLOBAL_TAG]='kuali-pdf-s3'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
)


# Create, update, or delete the cloudformation stack for kuali research.
stackAction() {  
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws --profile=$PROFILE cloudformation $action --stack-name $STACK_NAME
    
    [ $? -gt 0 ] && echo "Cancelling..." && return 1
  elif [ -z "$CAMPUS_SUBNET_ID" ] ; then
      echo "CAMPUS_SUBNET_ID parameter required! Cancelling."
      exit 1
  else
    local VpcId="$(getVpcId $CAMPUS_SUBNET_ID)"

    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    # If creating the stack, create and import a keypair to configure the ec2 instance with for shell access.
    if [ "$action" == 'create-stack' ] ; then
      createEc2KeyPair $KEYPAIR_NAME
      [ -f "$KEYPAIR_NAME" ] && chmod 600 $KEYPAIR_NAME
    fi

    cat <<-EOF > $cmdfile
    aws --profile=$PROFILE \\
      cloudformation $action \\
      --stack-name $STACK_NAME \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/ec2.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $VpcId
    addParameter $cmdfile 'CampusSubnet' $CAMPUS_SUBNET_ID
    [ -n "$PDF_IMAGE" ] && \
      addParameter $cmdfile 'PdfImage' $PDF_IMAGE
    [ -n "$KC_IMAGE" ] && \
      addParameter $cmdfile 'KcImage' $KC_IMAGE
    [ -n "$CORE_IMAGE" ] && \
      addParameter $cmdfile 'CoreImage' $CORE_IMAGE
    [ -n "$PORTAL_IMAGE" ] && \
      addParameter $cmdfile 'PortalImage' $PORTAL_IMAGE
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
    [ -n "$KEYPAIR_NAME" ] && \
      addParameter $cmdfile 'EC2KeypairName' $KEYPAIR_NAME

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

run() {
  if ! isCurrentDir "kuali_ec2" ; then
    echo "You must run this script from the kuali_ec2 subdirectory!."
    exit 1
  fi

  source ../scripts/common-functions.sh

  task="${1,,}"
  shift

  parseArgs $@

  setDefaults

  runTask
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
    test)
      test ;;
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