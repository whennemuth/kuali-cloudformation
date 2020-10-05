#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2'
  [GLOBAL_TAG]='kuali-ec2'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2'
  [TEMPLATE_PATH]='.'
  [KC_IMAGE]='getLatestImage kuali-coeus-sandbox'
  [CORE_IMAGE]='getLatestImage kuali-core'
  [PORTAL_IMAGE]='getLatestImage kuali-portal'
  [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [KEYPAIR_NAME]='kuali-ec2-$LANDSCAPE-keypair'
  [PDF_BUCKET_NAME]='kuali-pdf-$LANDSCAPE'
  # -----------------------------------------------
  # No defaults - user must provide explicit value:
  # -----------------------------------------------
  #   [CAMPUS_SUBNET1]='???'
  # -----------------------------------------------
  # The following are defaulted in the yaml file itself, but can be overridden:
  # -----------------------------------------------
  #   [TEMPLATE]='main.yaml'

)

run() {

  source ../scripts/common-functions.sh
  
  if ! isCurrentDir "kuali_ec2" ; then
    echo "You must run this script from the kuali_ec2 subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] ; then

    parseArgs $@

    setDefaults
  fi

  runTask
}


# Create, update, or delete the cloudformation stack.
stackAction() {  
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    if [ -n "$PDF_BUCKET_NAME" ] ; then
      if bucketExists "$PDF_BUCKET_NAME" ; then
        # Cloudformation can only delete a bucket if it is empty (and has no versioning), so empty it out here.
        aws --profile=$PROFILE s3 rm s3://$PDF_BUCKET_NAME --recursive
        # aws --profile=$PROFILE s3 rb --force $PDF_BUCKET_NAME
      fi
    fi
    
    [ $? -gt 0 ] && echo "Cancelling..." && return 1

    aws --profile=$PROFILE cloudformation $action --stack-name ${STACK_NAME}-${LANDSCAPE}
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
      exit 1
    fi

    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1
    # Upload scripts that will be run as part of AWS::CloudFormation::Init
    aws s3 cp ../scripts/ec2/process-configs.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/
    aws s3 cp ../scripts/ec2/stop-instance.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/
    aws s3 cp ../scripts/ec2/cloudwatch-metrics.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/

    case "$action" in
      create-stack)
        # Prompt to create the keypair, even if it already exists (offer choice to replace with new one).
        createEc2KeyPair $KEYPAIR_NAME
        [ -f "$KEYPAIR_NAME" ] && chmod 600 $KEYPAIR_NAME
        ;;
      update-stack)
        # Create the keypair without prompting, but only if it does not already exist
        if ! keypairExists $KEYPAIR_NAME ; then
          createEc2KeyPair $KEYPAIR_NAME
          [ -f "$KEYPAIR_NAME" ] && chmod 600 $KEYPAIR_NAME
        fi
        ;;
    esac

    cat <<-EOF > $cmdfile
    aws --profile=$PROFILE \\
      cloudformation $action \\
      --stack-name ${STACK_NAME}-${LANDSCAPE} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/ec2.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $VpcId
    addParameter $cmdfile 'CampusSubnet' $CAMPUS_SUBNET1
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

    # The cloudformation template has instructions to create the pdf bucket with the name you provide
    # or a default name unless you explicitly tell it "cancel". There are 2 "cancel" scenarios.
    if [ -n "$PDF_BUCKET_NAME" ] ; then
      if bucketExists "$PDF_BUCKET_NAME" ; then
        PDF_BUCKET_NAME="cancel"
      else
        addParameter $cmdfile 'PdfS3BucketName' $PDF_BUCKET_NAME
      fi
    elif bucketExists "kuali-pdf-$LANDSCAPE" ; then
      # The bucket with the default name already exists.
      PDF_BUCKET_NAME="cancel"
    fi      

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
    keys)
      createEc2KeyPair ;;
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