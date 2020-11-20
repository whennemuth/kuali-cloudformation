#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2-alb'
  [GLOBAL_TAG]='kuali-ec2-alb'
  [LANDSCAPE]='sb'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2_alb'
  [TEMPLATE_PATH]='.'
  [CN]='kuali-research.bu.edu'
  [ROUTE53]='true'
  [KC_IMAGE]='getLatestImage kuali-coeus'
  [CORE_IMAGE]='getLatestImage kuali-core'
  [PORTAL_IMAGE]='getLatestImage kuali-portal'
  [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  # [KC_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-sandbox:2001.0040'
  # [CORE_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-core:2001.0040'
  # [PORTAL_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-portal:2001.0040'
  # [PDF_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-research-pdf:2002.0003'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [PDF_BUCKET_NAME]='$GLOBAL_TAG-pdf-$LANDSCAPE'
  [USING_ROUTE53]='false'
  [CREATE_MONGO]='false'
  [ENABLE_ALB_LOGGING]='false'
  [DEEP_VALIDATION]='true'
  [CREATE_WAF]='true'
  # ----- Most of the following are defaulted in the yaml file itself:
  # [ENABLE_ALB_LOGGING]='false'
  # [KEYPAIR_NAME]='kuali-keypair-$LANDSCAPE'
  # [EC2_INSTANCE_TYPE]='m4.medium'
  # [VPC_ID]='???'
  # [CAMPUS_SUBNET1]='???'
  # [PUBLIC_SUBNET1]='???'
  # [CAMPUS_SUBNET2]='???'
  # [PUBLIC_SUBNET2]='???'
  # [CERTIFICATE_ARN]='???'
  # [TEMPLATE]='main.yaml'
  # [LOGICAL_RESOURCE_ID]='???'
  # [ENABLE_NEWRELIC_APM]='false'
  # [ENABLE_NEWRELIC_INFRASTRUCTURE]='false'
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_ec2_alb" ; then
    echo "You must run this script from the kuali_ec2_alb subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    checkLegacyAccount

    setDefaults
  fi

  runTask
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then

    # Cloudformation can only delete a bucket if it is empty (and has no versioning), so empty it out here.
    # if ! emptyBuckets \
    #   "$PDF_BUCKET_NAME" \
    #   "${GLOBAL_TAG}-${LANDSCAPE}-athena" \
    #   "${GLOBAL_TAG}-${LANDSCAPE}-waf" \
    #   "${GLOBAL_TAG}-${LANDSCAPE}-alb" ; then
    #   "Cancelling..." && return 1
    # fi

    # Lambda function will stop logging and clear out related buckets.
    
    aws --profile=$PROFILE cloudformation $action --stack-name ${STACK_NAME}-${LANDSCAPE}
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
      exit 1
    fi

    # Get the arn of any ssl cert (acm or self-signed in iam)
    setCertArn

    checkKeyPair

    # Validate and upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    if [ "$DEEP_VALIDATION" == 'true' ] ; then
      if [ "${CREATE_MONGO,,}" == 'true' ] ; then
        validateStack silent ../kuali_mongo/mongo.yaml > /dev/null
        [ $? -gt 0 ] && exit 1
        aws s3 cp ../kuali_mongo/mongo.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_mongo/
        aws s3 cp ../scripts/ec2/initialize-mongo-database.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
      fi
      if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
        validateStack silent ../kuali_alb/logs.yaml > /dev/null
        [ $? -gt 0 ] && exit 1
        aws s3 cp ../kuali_alb/logs.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_alb/

        validateStack silent ../kuali_waf/waf.yaml
        [ $? -gt 0 ] && exit 1
        aws s3 cp ../kuali_waf/waf.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

        validateStack silent ../kuali_waf/aws-waf-security-automations-custom.yaml
        [ $? -gt 0 ] && exit 1
        aws s3 cp ../kuali_waf/aws-waf-security-automations-custom.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

        validateStack silent ../kuali_waf/aws-waf-security-automations-webacl-custom.yaml
        [ $? -gt 0 ] && exit 1
        aws s3 cp ../kuali_waf/aws-waf-security-automations-webacl-custom.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

        # validateStack silent ../lambda/pre-alb-delete/cleanup.yaml
        # [ $? -gt 0 ] && exit 1
        # aws s3 cp ../lambda/pre-alb-delete/cleanup.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/
      fi

      # Upload scripts that will be run as part of AWS::CloudFormation::Init
      aws s3 cp ../kuali_alb/alb.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_alb/
      aws s3 cp ../scripts/ec2/process-configs.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
      aws s3 cp ../scripts/ec2/stop-instance.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/
      aws s3 cp ../scripts/ec2/cloudwatch-metrics.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/

      # Upload lambda code used by custom resources
      # if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
      #   if [ -f ../lambda/pre-alb-delete/cleanup.js ] ; then
      #     zipAndCopyToS3 \
      #       s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/cleanup.zip \
      #       ../lambda/pre-alb-delete/cleanup.js \
      #       ../lambda/cfn-response.js
      #   else
      #     echo "ERROR! Cannot find "../lambda/pre-alb-delete/cleanup.js" for upload to s3";
      #     exit 1
      #   fi
      # fi
    fi

    cat <<-EOF > $cmdfile
    aws --profile=$PROFILE \\
      cloudformation $action \\
      --stack-name ${STACK_NAME}-${LANDSCAPE} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/main.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'CampusSubnet1' 'CAMPUS_SUBNET1'
    add_parameter $cmdfile 'CampusSubnet2' 'CAMPUS_SUBNET2'
    add_parameter $cmdfile 'PublicSubnet1' 'PUBLIC_SUBNET1'
    add_parameter $cmdfile 'PublicSubnet2' 'PUBLIC_SUBNET2'
    add_parameter $cmdfile 'CertificateArn' 'CERTIFICATE_ARN'
    add_parameter $cmdfile 'PdfImage' 'PDF_IMAGE'
    add_parameter $cmdfile 'KcImage' 'KC_IMAGE'
    add_parameter $cmdfile 'CoreImage' 'CORE_IMAGE'
    add_parameter $cmdfile 'PortalImage' 'PORTAL_IMAGE'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'EC2InstanceType' 'EC2_INSTANCE_TYPE'
    add_parameter $cmdfile 'EnableNewRelicAPM' 'ENABLE_NEWRELIC_APM'
    add_parameter $cmdfile 'EnableNewRelicInfrastructure' 'ENABLE_NEWRELIC_INFRASTRUCTURE'
    add_parameter $cmdfile 'EC2KeypairName' 'KEYPAIR_NAME'
    add_parameter $cmdfile 'EnableWAF' 'CREATE_WAF'
    add_parameter $cmdfile 'EnableALBLogging' 'ENABLE_ALB_LOGGING'

    if [ "${CREATE_MONGO,,}" == 'true' ] ; then
      add_parameter $cmdfile 'MongoSubnetId' 'PRIVATE_SUBNET1'
    fi

    if [ "${USING_ROUTE53,,}" == 'true' ] ; then
      HOSTED_ZONE_NAME="$(getHostedZoneNameByLandscape $LANDSCAPE)"
      [ -z "$HOSTED_ZONE_NAME" ] && echo "ERROR! Cannot acquire hosted zone name. Cancelling..." && exit 1
      add_parameter $cmdfile 'HostedZoneName' 'HOSTED_ZONE_NAME'
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
    cert)
      createSelfSignedCertificate ;;
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
    set-cert-arn)
      setCertArn ;;
    test)
      cd ../s3/ci
      AWS_PROFILE=infnprd
      setAcmCertArn 'kuali-research.bu.edu'
      # setAcmCertArn 'kuali-research-css-ci.bu.edu'
      
      # sh main.sh set-cert-arn \
      #   profile=infnprd \
      #   landscape=ci 
      ;;
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