#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2-alb'
  [GLOBAL_TAG]='kuali-ec2-alb'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2_alb'
  [TEMPLATE_PATH]='.'
  [KC_IMAGE]='getLatestImage repo_name=kuali-coeus'
  [CORE_IMAGE]='getLatestImage repo_name=kuali-core'
  [PORTAL_IMAGE]='getLatestImage repo_name=kuali-portal'
  [PDF_IMAGE]='getLatestImage repo_name=kuali-research-pdf'
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
  # [JUMPBOX_INSTANCE_TYPE]='???'
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_ec2_alb" ; then
    echo "You must run this script from the kuali_ec2_alb subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    checkLegacyAccount

    setDefaults

    validateShibboleth
  fi

  runTask
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  [ -z "$FULL_STACK_NAME" ] && FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $(getStackToDelete)
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

    # Get the arn of any ssl cert (acm or self-signed in iam)
    outputHeading "Checking certificates..."
    setCertArn

    checkKeyPair

    if [ "${SKIP_S3_UPLOAD,,}" == 'true' ] ; then
      echo "Skipping upload of templates and scripts to s3."
    else
      # Validate and upload the yaml files to s3
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
      for f in $(find ../scripts/ec2/ -type f -iname '*.sh') ; do
        copyToBucket $f "s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/"
      done
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
    elif [ -n "$RDS_ARN" ] ; then
      if [ "${USING_ROUTE53,,}" == 'true' ] ; then
        if rdsInstanceRoute53RecordExists $RDS_ARN $HOSTED_ZONE $LANDSCAPE ; then
          echo "No RDS snapshotting indicated. Will use: $RDS_ARN"
          echo "        arn: $RDS_ARN"
          echo "   endpoint: $RDS_INSTANCE_ROUTE53_RECORD"
          addParameter $cmdfile 'RdsRoute53Endpoint' "$RDS_INSTANCE_ROUTE53_RECORD"
        else
          echo "No RDS snapshotting indicated. Will use: $RDS_ARN"
          validateTemplateAndUploadToS3 \
            silent=true \
            filepath=../kuali_rds/rds-dns.yaml \
            s3path=s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_rds/
          # The route53 CNAME record does not yet exist but will get created further along in the stack, so set the anticipated value for the rds endpoint
          addParameter $cmdfile 'RdsRoute53Endpoint' "${LANDSCAPE}.db.${HOSTED_ZONE}"
          addParameter $cmdfile 'RdsPrivateEndpoint' "$(getRdsEndpoint $RDS_ARN)"
          addParameter $cmdfile 'RdsVpcSecurityGroupId' "$(getRdsVpcSecurityGroupId $RDS_ARN)"
        fi
      else
        echo "No RDS snapshotting indicated. Will use: $RDS_ARN"
        addParameter $cmdfile 'RdsPrivateEndpoint' "$(getRdsEndpoint $RDS_ARN)"
        addParameter $cmdfile 'RdsVpcSecurityGroupId' "$(getRdsVpcSecurityGroupId $RDS_ARN)"
      fi
    else
      # Is there a scenario where the db is specified some other way, or should it exit here with an error code?
      echo "WARNING: No RDS snapshotting indicated and no rds arn provided - how is the database for this stack specified?"
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
    addTag $cmdfile 'Subcategory' 'ec2-alb'
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
    test)
      # cd ../s3/ci
      # setAcmCertArn 'kuali.research.bu.edu'
      
      sh main.sh set-cert-arn \
        landscape=ci \
        USING_ROUTE53=true
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