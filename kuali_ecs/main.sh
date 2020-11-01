#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ecs'
  [GLOBAL_TAG]='kuali-ecs'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ecs'
  [TEMPLATE_PATH]='.'
  [CN]='kuali-research.bu.edu'
  [ROUTE53]='true'
  # [KC_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-sandbox:2001.0040'
  # [CORE_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-core:2001.0040'
  # [PORTAL_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-portal:2001.0040'
  # [PDF_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-research-pdf:2002.0003'
  [KC_IMAGE]='getLatestImage kuali-coeus'
  [CORE_IMAGE]='getLatestImage kuali-core'
  [PORTAL_IMAGE]='getLatestImage kuali-portal'
  [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [PDF_BUCKET_NAME]='$GLOBAL_TAG-pdf-$LANDSCAPE'
  [USING_ROUTE53]='false'
  [CREATE_MONGO]='false'
  [ENABLE_ALB_LOGGING]='false'
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
  # [MIN_CLUSTER_SIZE]='2'
  # [MAX_CLUSTER_SIZE]='3'
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_ecs" ; then
    echo "You must run this script from the kuali_ecs subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    checkLegacyAccount

    setDefaults

    validateParms
  fi

  runTask
}

validateParms() {
  local msg=''
  if [ -z "$MIN_CLUSTER_SIZE" ] && [ -z "$MAX_CLUSTER_SIZE" ] ; then
    # Invoke the parameter defaults of the main.yaml template for cluster size
    return 0
  elif [ -n "$MIN_CLUSTER_SIZE" ] && [ -n "$MAX_CLUSTER_SIZE" ] ; then
    if [ $MIN_CLUSTER_SIZE -gt $MAX_CLUSTER_SIZE ] ; then
      msg='Minimum cluster size cannot be greater than maximum cluster size.'
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
    
    # Get the arn of any ssl cert (acm or self-signed in iam)
    setCertArn

    checkKeyPair

    # Validate and upload the yaml file(s) to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    if [ "${CREATE_MONGO,,}" == 'true' ] ; then
      echo "validating ../kuali_mongo/mongo.yaml..."
      validate ../kuali_mongo/mongo.yaml > /dev/null
      [ $? -gt 0 ] && exit 1
      aws s3 cp ../kuali_mongo/mongo.yaml s3://$BUCKET_NAME/cloudformation/kuali_mongo/
      aws s3 cp ../scripts/ec2/initialize-mongo-database.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/
    fi
    if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
      echo "validating ../kuali_alb/logs.yaml..."
      validate ../kuali_alb/logs.yaml > /dev/null
      [ $? -gt 0 ] && exit 1
      aws s3 cp ../kuali_alb/logs.yaml s3://$BUCKET_NAME/cloudformation/kuali_alb/

      echo "validating ../kuali_waf/waf.yaml..."
      [ $? -gt 0 ] && exit 1
      aws s3 cp ../kuali_waf/waf.yaml s3://$BUCKET_NAME/cloudformation/kuali_waf/

      echo "validating ../lambda/pre-alb-delete/cleanup.yaml..."
      [ $? -gt 0 ] && exit 1
      aws s3 cp ../lambda/pre-alb-delete/cleanup.yaml s3://$BUCKET_NAME/cloudformation/kuali_lambda/
    fi

    # Upload scripts that will be run as part of AWS::CloudFormation::Init
    aws s3 cp ../kuali_alb/alb.yaml s3://$BUCKET_NAME/cloudformation/kuali_alb/
    aws s3 cp ../scripts/ec2/process-configs.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/
    aws s3 cp ../scripts/ec2/cloudwatch-metrics.sh s3://$BUCKET_NAME/cloudformation/scripts/ec2/

    # Upload lambda code used by custom resources
    if [ "${ENABLE_ALB_LOGGING,,}" != 'false' ] || [ "${CREATE_WAF,,}" == 'true' ] ; then
      if [ -f ../lambda/pre-alb-delete/cleanup.js ] ; then
        cat ../lambda/pre-alb-delete/cleanup.js | gzip -f --keep --stdout | aws s3 cp - s3://$BUCKET_NAME/cloudformation/kuali_lambda/cleanup.zip
      else
        echo "ERROR! Cannot find "../lambda/pre-alb-delete/cleanup.js" for upload to s3";
        exit 1
      fi
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
    add_parameter $cmdfile 'MinClusterSize' 'MIN_CLUSTER_SIZE'
    add_parameter $cmdfile 'MaxClusterSize' 'MAX_CLUSTER_SIZE'
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
      PROFILE=infnprd && checkSubnets ;;
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