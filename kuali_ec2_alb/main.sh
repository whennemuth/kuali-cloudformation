#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-ec2-alb'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-research-ec2-setup/cloudformation/kuali_ec2_alb'
  [TEMPLATE_PATH]='.'
  [KC_IMAGE]='730096353738.dkr.ecr.us-east-1.amazonaws.com/coeus-sandbox:2001.0040'
  [CORE_IMAGE]='730096353738.dkr.ecr.us-east-1.amazonaws.com/core:2001.0040'
  [PORTAL_IMAGE]='730096353738.dkr.ecr.us-east-1.amazonaws.com/portal:2001.0040'
  [PDF_IMAGE]='730096353738.dkr.ecr.us-east-1.amazonaws.com/research-pdf:2002.0003'
  [GLOBAL_TAG]='kuali-ec2-alb'
  [NO_ROLLBACK]='true'
  # ----- Most of the following are defaulted in the yaml file itself:
  # [EC2_INSTANCE_TYPE]='m4.medium'
  # [AVAILABILITY_ZONE1]='us-east-1a'
  # [AVAILABILITY_ZONE2]='us-east-1b'
  # [VPC_ID]='???'
  # [INTERNET_GATEWAY_ID]='???'
  # [PRIVATE_SUBNET1]='???'
  # [PUBLIC_SUBNET1]='???'
  # [PRIVATE_SUBNET2]='???'
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

  parseArgs $@

  setDefaults

  runTask
}


# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $STACK_NAME
    
    [ $? -gt 0 ] && echo "Cancelling..." && return 1
  else
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
The certificate ARN not found in any of the sources.
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

    # Get the default vpc id if needed, and get the id of the internet gateway in the vpc
    [ -z "$VPC_ID" ] && VPC_ID=$(getDefaultVpcId)
    echo "Using default vpc: $VPC_ID"
    [ -z "$INTERNET_GATEWAY_ID" ] && INTERNET_GATEWAY_ID=$(getInternetGatewayId $VPC_ID)
    [ -z "$INTERNET_GATEWAY_ID" ] && echo "ERROR! Cannot determine internet gateway id" && exit 1
    echo "Using default vpc internet gateway: $INTERNET_GATEWAY_ID"

    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name $STACK_NAME \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ]) && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/YAML \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF
    addParameter $cmdfile 'VpcId' $VPC_ID
    addParameter $cmdfile 'InternetGatewayId' $INTERNET_GATEWAY_ID
    addParameter $cmdfile 'CertificateArn' $certArn
    addParameter $cmdfile 'KcImage' $KC_IMAGE
    addParameter $cmdfile 'CoreImage' $CORE_IMAGE
    addParameter $cmdfile 'PortalImage' $PORTAL_IMAGE
    addParameter $cmdfile 'PdfImage' $PDF_IMAGE

    # Chose which yaml starting point to use for the stack creation/update.
    if subnetsProvided ; then
      sed -i 's/YAML/main-existing-subnets.yaml/' $cmdfile
      addParameter $cmdfile 'PublicSubnet1' $PUBLIC_SUBNET1
      addParameter $cmdfile 'PrivateSubnet1' $PRIVATE_SUBNET1
      addParameter $cmdfile 'PublicSubnet2' $PUBLIC_SUBNET2
      addParameter $cmdfile 'PrivateSubnet2' $PRIVATE_SUBNET2
    else
      sed -i 's/YAML/main-create-subnets.yaml/' $cmdfile
    fi

    # Add on any other parameters that were explicitly provided
    [ -n "$LANDSCAPE" ] && \
      addParameter $cmdfile 'Landscape' $LANDSCAPE
    [ -n "$GLOBAL_TAG" ] && \
      addParameter $cmdfile 'GlobalTag' $GLOBAL_TAG
    [ -n "$BUCKET_NAME" ] && \
      addParameter $cmdfile 'BucketName' $BUCKET_NAME
    [ -n "$EC2_INSTANCE_TYPE" ] && \
      addParameter $cmdfile 'EC2InstanceType' $EC2_INSTANCE_TYPE
    [ -n "$ENABLE_NEWRELIC_APM" ] && \
      addParameter $cmdfile 'EnableNewRelicAPM' $ENABLE_NEWRELIC_APM
    [ -n "$ENABLE_NEWRELIC_INFRASTRUCTURE" ] && \
      addParameter $cmdfile 'EnableNewRelicInfrastructure' $ENABLE_NEWRELIC_INFRASTRUCTURE
    [ -n "$AVAILABILITY_ZONE1" ] && \
      addParameter $cmdfile 'AvailabilityZone1' $AVAILABILITY_ZONE1
    [ -n "$AVAILABILITY_ZONE2" ] && \
      addParameter $cmdfile 'AvailabilityZone2' $AVAILABILITY_ZONE2

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
  case $task in
    docker-build)
      build ;;
    docker-run)
      run ;;
    docker-push)
      push ;;
    keys)
      createEc2KeyPair ;;
    cert)
      createSelfSignedCertificate ;;
    create-stack)
      stackAction 'create-stack' ;;
    update-stack)
      stackAction 'update-stack' ;;
    delete-stack)
      stackAction 'delete-stack' ;;
    validate)
      validateStack ;;
    upload)
      uploadStack ;;
    test)
      getSelfSignedArn ;;
  esac
}

run $@