#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ecs'
  [GLOBAL_TAG]='kuali-ecs'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ecs'
  [TEMPLATE_PATH]='.'
  [KC_IMAGE]='getLatestImage kuali-coeus'
  [CORE_IMAGE]='getLatestImage kuali-core'
  [PORTAL_IMAGE]='getLatestImage kuali-portal'
  [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  [NO_ROLLBACK]='true'
  [PDF_BUCKET_NAME]='$GLOBAL_TAG-$LANDSCAPE-pdf'
  [DEEP_VALIDATION]='true'
  [HOSTED_ZONE]='kuali.research.bu.edu'
  # ----- Most of the following are defaulted in the yaml file itself:
  # [PROFILE]='???'
  # [LANDSCAPE]='sb'
  # [KC_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-sandbox:2001.0040'
  # [CORE_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-core:2001.0040'
  # [PORTAL_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-portal:2001.0040'
  # [PDF_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-research-pdf:2002.0003'
  # [USING_ROUTE53]='false'
  # [USING_SHIBBOLETH]='false'
  # [CREATE_MONGO]='false'
  # [ENABLE_ALB_LOGGING]='false'
  # [CREATE_WAF]='false'
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
  # [NEWRELIC_LICENSE_KEY]='???'
  # [ENABLE_NEWRELIC_APM]='false'
  # [ENABLE_NEWRELIC_INFRASTRUCTURE]='false'
  # [MIN_CLUSTER_SIZE]='2'
  # [MAX_CLUSTER_SIZE]='3'
  # [JUMPBOX_INSTANCE_TYPE]='???'
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_ecs" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the kuali_ecs subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    checkLegacyAccount

    setDefaults

    validateParms
  fi

  runTask
}

validateCluster() {
  [ "$task" == 'delete-stack' ] && return 0
  if [ -z "$MIN_CLUSTER_SIZE" ] && [ -z "$MAX_CLUSTER_SIZE" ] ; then
    # Invoke the parameter defaults of the main.yaml template for cluster size
    return 0
  elif [ -n "$MIN_CLUSTER_SIZE" ] && [ -n "$MAX_CLUSTER_SIZE" ] ; then
    if [ $MIN_CLUSTER_SIZE -gt $MAX_CLUSTER_SIZE ] ; then
      echo 'Minimum cluster size cannot be greater than maximum cluster size.'
      exit 1
    fi  
  elif [ -z "$MIN_CLUSTER_SIZE" ] ; then
    MIN_CLUSTER_SIZE=$((MAX_CLUSTER_SIZE-1))
  elif [ -z "$MAX_CLUSTER_SIZE "] ; then
    MAX_CLUSTER_SIZE=$((MIN_CLUSTER_SIZE+1))
  fi
  if [ $MIN_CLUSTER_SIZE -eq 0 ] ; then
    $((MIN_CLUSTER_SIZE++))
  fi
}

validateParms() {

  validateCluster

  validateShibboleth
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1   

  [ -z "$FULL_STACK_NAME" ] && FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $FULL_STACK_NAME
    if ! waitForStackToDelete ; then
      echo "Problem deleting stack!"
      exit 1
    fi
  else

    # checkSubnets will also assign a value to VPC_ID
    outputHeading "Looking up VPC/Subnet information..."
    if ! checkSubnets ; then
      exit 1
    fi
    
    outputHeading "Checking certificates..."
    # Get the arn of any ssl cert (acm or self-signed in iam)
    setCertArn

    checkKeyPair

    if [ "${SKIP_S3_UPLOAD,,}" == 'true' ] ; then
      echo "Skipping upload of templates and scripts to s3."
    else
      # Validate and upload the yaml file(s) to s3
      outputHeading "Validating and uploading main template(s)..."
      uploadStack silent
      [ $? -gt 0 ] && exit 1

      if [ "$DEEP_VALIDATION" == 'true' ] ; then
        outputHeading "Validating and uploading nested templates..."
        if [ "${CREATE_MONGO,,}" == 'true' ] ; then
          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_mongo/mongo.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_mongo/

          copyToBucket '../scripts/ec2/initialize-mongo-database.sh' "s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/"

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_campus_security/main.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_campus_security/
        fi
        if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_alb/logs.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_alb/

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_waf/waf.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_waf/aws-waf-security-automations-custom.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_waf/aws-waf-security-automations-webacl-custom.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_waf/

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../lambda/toggle_alb_logging/toggle_alb_logging.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/

          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../lambda/toggle_waf_logging/toggle_waf_logging.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/
        fi

        validateTemplateAndUploadToS3 \
          silent=true \
          filepath=../kuali_alb/alb.yaml \
          s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_alb/

        validateTemplateAndUploadToS3 \
          silent=true \
          filepath=../lambda/bucket_emptier/bucket_emptier.yaml \
          s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/

        # Upload lambda code used by custom resources
        outputHeading "Building, zipping, and uploading lambda code behind custom resources..."
        zipPackageAndCopyToS3 '../lambda/bucket_emptier' 's3://kuali-conf/cloudformation/kuali_lambda/bucket_emptier.zip'
        [ $? -gt 0 ] && echo "ERROR! Could not upload bucket_emptier.zip to s3." && exit 1
        if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
          zipPackageAndCopyToS3 '../lambda/toggle_alb_logging' 's3://kuali-conf/cloudformation/kuali_lambda/toggle_alb_logging.zip'
          [ $? -gt 0 ] && echo "ERROR! Could not upload toggle_alb_logging.zip to s3." && exit 1
          
          zipPackageAndCopyToS3 '../lambda/toggle_waf_logging' 's3://kuali-conf/cloudformation/kuali_lambda/toggle_waf_logging.zip'
          [ $? -gt 0 ] && echo "ERROR! Could not upload toggle_waf_logging.zip to s3." && exit 1
        fi
      fi

      # Upload scripts that will be run as part of AWS::CloudFormation::Init
      outputHeading "Uploading bash scripts involved in AWS::CloudFormation::Init..."
      copyToBucket '../scripts/ec2/process-configs.sh' "s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/"
      copyToBucket '../scripts/ec2/cloudwatch-metrics.sh' "s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/"
    fi

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${FULL_STACK_NAME} \\
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
    add_parameter $cmdfile 'NewrelicLicsenseKey' 'NEWRELIC_LICENSE_KEY'
    add_parameter $cmdfile 'EnableNewRelicAPM' 'ENABLE_NEWRELIC_APM'
    add_parameter $cmdfile 'EnableNewRelicInfrastructure' 'ENABLE_NEWRELIC_INFRASTRUCTURE'
    add_parameter $cmdfile 'EC2KeypairName' 'KEYPAIR_NAME'
    add_parameter $cmdfile 'MinClusterSize' 'MIN_CLUSTER_SIZE'
    add_parameter $cmdfile 'MaxClusterSize' 'MAX_CLUSTER_SIZE'
    add_parameter $cmdfile 'EnableWAF' 'CREATE_WAF'
    add_parameter $cmdfile 'EnableALBLogging' 'ENABLE_ALB_LOGGING'
    add_parameter $cmdfile 'RetainLambdaCleanupLogs' 'RETAIN_LAMBDA_CLEANUP_LOGS'
    add_parameter $cmdfile 'UsingShibboleth' 'USING_SHIBBOLETH'
    add_parameter $cmdfile 'RdsJumpboxInstanceType' 'JUMPBOX_INSTANCE_TYPE'

    if [ "${CREATE_MONGO,,}" == 'true' ] ; then
      add_parameter $cmdfile 'MongoSubnetId' 'PRIVATE_SUBNET1'
    fi

    if [ "${USING_ROUTE53,,}" == 'true' ] ; then
      # HOSTED_ZONE_NAME="$(getHostedZoneNameByLandscape $LANDSCAPE)"
      # [ -z "$HOSTED_ZONE_NAME" ] && echo "ERROR! Cannot acquire hosted zone name. Cancelling..." && exit 1
      # add_parameter $cmdfile 'HostedZoneName' 'HOSTED_ZONE_NAME'
      [ -z "$(getHostedZoneId $HOSTED_ZONE)" ] && echo "ERROR! Cannot detect hosted zone for $HOSTED_ZONE" && exit 1
      addParameter $cmdfile 'HostedZoneName' $HOSTED_ZONE
    fi

    if [ "${PDF_BUCKET_NAME,,}" != 'none' ] ; then  
      add_parameter $cmdfile 'PdfS3BucketName' 'PDF_BUCKET_NAME'
    fi
    
    checkLandscapeParameters

    checkRDSParameters    # Based on landscape and other parameters, perform rds cloning if indicated.

    add_parameter $cmdfile 'Baseline' 'BASELINE'

    if [ -n "$RDS_SNAPSHOT_ARN" ] ; then
      validateTemplateAndUploadToS3 \
        silent=true \
        filepath=../kuali_rds/rds-oracle.yaml \
        s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_rds/

      processRdsParameters $cmdfile $LANDSCAPE "$RDS_SNAPSHOT_ARN" "$RDS_ARN_TO_CLONE"

      validateTemplateAndUploadToS3 \
        silent=true \
        filepath=../kuali_campus_security/main.yaml \
        s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_campus_security/
    else
      echo "No RDS snapshotting indicated. Will use existing RDS database directly."
    fi

    if [ -n "$JUMPBOX_INSTANCE_TYPE" ] ; then
      validateTemplateAndUploadToS3 \
        silent=true \
        filepath=../kuali_rds/jumpbox/jumpbox.yaml \
        s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_rds/jumpbox/
    fi

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'application'
    addTag $cmdfile 'Subcategory' 'ecs'
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
      task='create-stack'
      stackAction "create-stack"
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
    snapshot)
      echo "" > $cmdfile
      if [ -n "$RDS_SNAPSHOT_ARN" ]; then
        processRdsParameters $cmdfile $LANDSCAPE "$RDS_SNAPSHOT_ARN" "$RDS_ARN_TO_CLONE"
      fi
      ;;
    test)
      checkSubnets ;;
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