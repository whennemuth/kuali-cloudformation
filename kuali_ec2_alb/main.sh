#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2-alb'
  [GLOBAL_TAG]='kuali-ec2-alb'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2_alb'
  [TEMPLATE_PATH]='.'
  [CN]='kuali-research.bu.edu'
  [ROUTE53]='true'
  [KC_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-sandbox:2001.0040'
  [CORE_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-core:2001.0040'
  [PORTAL_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-portal:2001.0040'
  [PDF_IMAGE]='770203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-research-pdf:2002.0003'
  # [KC_IMAGE]='getLatestImage kuali-coeus-sandbox'
  # [CORE_IMAGE]='getLatestImage kuali-core'
  # [PORTAL_IMAGE]='getLatestImage kuali-portal'
  # [PDF_IMAGE]='getLatestImage kuali-research-pdf'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [KEYPAIR_NAME]='kuali-keypair-$LANDSCAPE'
  [PDF_BUCKET_NAME]='$GLOBAL_TAG-pdf-$LANDSCAPE'
  # ----- Most of the following are defaulted in the yaml file itself:
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

  if [ "$task" != "test" ] ; then

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
    add_parameter $cmdfile 'PdfS3BucketName' 'PDF_BUCKET_NAME'
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

    if [ "$ROUTE53" == 'true' ] ; then
      HOSTED_ZONE_ID="$(getHostedZoneId $CN)"
      [ -z "$hostedZoneId" ] && echo "ERROR! Could not obtain hosted zone id for $CN" && exit 1
      addParameter $cmdfile 'HostedZoneId' $hostedZoneId
      addParameter $cmdfile 'HostedZoneCommonName' $CN
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
    cert)
      createSelfSignedCertificate ;;
    create-stack)
      stackAction "create-stack" ;;
    update-stack)
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
    set-cert-arn)
      setCertArn ;;
    test)
      # cd ../s3/ci
      # setAcmCertArn 'kuali-research-css-ci.bu.edu'
      sh main.sh set-cert-arn \
        profile=infnprd \
        landscape=ci 
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