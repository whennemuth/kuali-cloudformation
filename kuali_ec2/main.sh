#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2'
  [GLOBAL_TAG]='kuali-ec2'
  # [LANDSCAPE]='sb'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2'
  [TEMPLATE_PATH]='.'
  [KC_IMAGE]='getLatestImage kuali-coeus'
  [CORE_IMAGE]='getLatestImage kuali-core'
  [PORTAL_IMAGE]='getLatestImage kuali-portal'
  [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [PDF_BUCKET_NAME]='$GLOBAL_TAG-$LANDSCAPE-pdf'
  [CREATE_MONGO]='false'
  # -----------------------------------------------
  # No defaults - user must provide explicit value:
  # -----------------------------------------------
  # [CAMPUS_SUBNET1]='???'
  # [KEYPAIR_NAME]='kuali-ec2-$LANDSCAPE-keypair'
  # -----------------------------------------------
  # The following are defaulted in the yaml file itself, but can be overridden:
  # -----------------------------------------------
  #   [TEMPLATE]='main.yaml'
  # [NEWRELIC_LICENSE_KEY]='???'
  # [ENABLE_NEWRELIC_APM]='false'
  # [ENABLE_NEWRELIC_INFRASTRUCTURE]='false'
)

run() {

  source ../scripts/common-functions.sh
  
  if ! isCurrentDir "kuali_ec2" ; then
    echo "You must run this script from the kuali_ec2 subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

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
    aws s3 cp ../scripts/ec2/process-configs.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
    aws s3 cp ../scripts/ec2/stop-instance.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
    aws s3 cp ../scripts/ec2/cloudwatch-metrics.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
    if [ "${CREATE_MONGO,,}" == 'true' ] ; then
      aws s3 cp ../kuali_mongo/mongo.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_mongo/
      aws s3 cp ../scripts/ec2/initialize-mongo-database.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
    fi

    checkKeyPair

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

    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'CampusSubnet' 'CAMPUS_SUBNET1'
    add_parameter $cmdfile 'PdfImage' 'PDF_IMAGE'
    add_parameter $cmdfile 'KcImage' 'KC_IMAGE'
    add_parameter $cmdfile 'CoreImage' 'CORE_IMAGE'
    add_parameter $cmdfile 'PortalImage' 'PORTAL_IMAGE'
    add_parameter $cmdfile 'EC2InstanceType' 'EC2_INSTANCE_TYPE'
    add_parameter $cmdfile 'NewrelicLicsenseKey' 'NEWRELIC_LICENSE_KEY'
    add_parameter $cmdfile 'EnableNewRelicAPM' 'ENABLE_NEWRELIC_APM'
    add_parameter $cmdfile 'EnableNewRelicInfrastructure' 'ENABLE_NEWRELIC_INFRASTRUCTURE'
    add_parameter $cmdfile 'EC2KeypairName' 'KEYPAIR_NAME'

    if [ "${CREATE_MONGO,,}" == 'true' ] ; then
      add_parameter $cmdfile 'MongoSubnetId' 'PRIVATE_SUBNET1'
    fi

    if [ "${PDF_BUCKET_NAME,,}" != 'none' ] ; then  
      add_parameter $cmdfile 'PdfS3BucketName' 'PDF_BUCKET_NAME'
    fi

    echo "      ]'" >> $cmdfile

    runStackActionCommand
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
    recreate-stack)
      PROMPT='false'
      task='delete-stack'
      stackAction "delete-stack" 2> /dev/null
      if waitForStackToDelete ${STACK_NAME}-${LANDSCAPE} ; then
        task='create-stack'
        stackAction "create-stack"
      else
        echo "ERROR! Stack deletion failed. Cancelling..."
      fi
      ;;
    update-stack)
      stackAction "update-stack" ;;
    reupdate-stack)
      PROMPT='false'
      task='update-stack'
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
    test)
      # getHostedZoneNameByLandscape 'ci' ;;
      # test ;;
      setAcmCertArn 'ci.kuali.research.bu.edu'
      echo $CERTIFICATE_ARN ;;
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