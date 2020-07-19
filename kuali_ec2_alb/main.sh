#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2-alb'
  [GLOBAL_TAG]='kuali-ec2-alb'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_ec2_alb'
  [TEMPLATE_PATH]='.'
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
  if [ "$(pwd | grep -oP '[^/]+$')" != "kuali_ec2_alb" ] ; then
    echo "You must run this script from the kuali_ec2_alb subdirectory!."
    exit 1
  fi

  source ../scripts/common-functions.sh

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
    
    aws --profile=$PROFILE cloudformation $action --stack-name $STACK_NAME
  else
    # checkSubnets will also assign a value to VPC_ID
    checkSubnets

    # Get the arn of the ssl cert
    certArn="$(getSelfSignedArn)"
    if [ -z "$certArn" ] ; then
      local askCreateCert=$(cat <<EOF

The load balancer will need a certificate for ssl.
Looking for the certificate ARN (amazon resource name).
Several sources are checked:
   - The "CERTIFICATE_ARN" parameter
   - A file containing the arn in the current directory
   - $BUCKET_PATH
The certificate ARN was not found in any of these sources.
Do you want to create and upload a new server certificate?
EOF
      ) 
      if askYesNo "$askCreateCert" ; then
        createSelfSignedCertificate
      fi
    fi
    certArn="$(getSelfSignedArn)"
    if [ -z "$certArn" ] ; then
      echo "Cannot proceed without a server certificate.\nCancelling..."
      exit 1
    fi
    echo "Using certificate: $certArn"

    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

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
      --stack-name $STACK_NAME \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/main.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $vpcId
    addParameter $cmdfile 'CampusSubnet1' $CAMPUS_SUBNET1
    addParameter $cmdfile 'CampusSubnet2' $CAMPUS_SUBNET2
    addParameter $cmdfile 'PublicSubnet1' $PUBLIC_SUBNET1
    addParameter $cmdfile 'PublicSubnet2' $PUBLIC_SUBNET2
    addParameter $cmdfile 'CertificateArn' $certArn
    addParameter $cmdfile 'PdfS3BucketName' $PDF_BUCKET_NAME

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
    test)
      getSelfSignedArn ;;
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