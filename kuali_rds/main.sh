#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-rds-oracle'
  [GLOBAL_TAG]='kuali-oracle'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [ENGINE]='oracle-se2'
  [MAJOR_VERSION]='19'
  [HOSTED_ZONE]='kuali.research.bu.edu'
  # ----- Some of the following are defaulted in the yaml file itself:
  # [LANDSCAPE]='???'
  # [PROFILE]='???'
  # [VPC_ID]='???'
  # [CAMPUS_SUBNET1]='???'
  # [CAMPUS_SUBNET2]='???'
  # [CAMPUS_SUBNET1_CIDR]='???'
  # [CAMPUS_SUBNET2_CIDR]='???'
  # [PUBLIC_SUBNET1]='???'
  # [PUBLIC_SUBNET2]='???'
  # [PUBLIC_SUBNET1_CIDR]='???'
  # [PUBLIC_SUBNET2_CIDR]='???'
  # [PRIVATE_SUBNET1]='???'
  # [PRIVATE_SUBNET2]='???'
  # [PRIVATE_SUBNET1_CIDR]='???'
  # [PRIVATE_SUBNET2_CIDR]='???'
  # [PRIVATE_SUBNET1_AZ]='???'
  # [LICENSE_MODEL]='???'
  # [DB_INSTANCE_CLASS]='???'
  # [ENGINE_VERSION]='???'
  # [DB_NAME]='???'
  # [PORT]='???'
  # [MULTI_AZ]='???'
  # [ALLOCATED_STORAGE]='???'
  # [RDS_SNAPSHOT_ARN]='???'
  # [AUTO_MINOR_VERSION_UPGRADE]='???'
  # [BACKUP_RETENTION_PERIOD]='???'
  # [CHARACTERSET_NAME]='???'
  # [IOPS]='???'
  # [JUMPBOX_INSTANCE_TYPE]='???'
  # [USING_ROUTE53]='false'
)


run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_rds" ; then
    echo "You must run this script from the kuali_rds subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" == 'get-secret' ] || [ "$task" == 'get-password' ] || [ "$task" == 'set-rds-access' ] ; then
    # Operate silently so that only the desired content shows up without the extra console output.
    parseArgs $@ 1> /dev/null

    checkLegacyAccount 1> /dev/null

    setDefaults 1> /dev/null

  elif [ "$task" != "test" ] ; then

    parseArgs $@

    checkLegacyAccount

    setDefaults
  fi

  runTask $@
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  [ -z "$FULL_STACK_NAME" ] && FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $FULL_STACK_NAME
  else
    # checkSubnets will also assign a value to VPC_ID
    if [ "$LEGACY_ACCOUNT" ] ; then
      if ! checkSubnetsInLegacyAccount ; then
        exit 1
      fi
    elif ! checkSubnets ; then
      exit 1
    fi

    # Upload the yaml file(s) to s3
    uploadStack
    [ $? -gt 0 ] && exit 1
    # Upload scripts that will be run as part of AWS::CloudFormation::Init
    aws s3 cp ../scripts/ec2/stop-instance.sh s3://$TEMPLATE_BUCKET_NAME/cloudformation/scripts/ec2/

    validateStack silent=true filepath=../kuali_campus_security/main.yaml
    [ $? -gt 0 ] && exit 1
    aws s3 cp ../kuali_campus_security/main.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_campus_security/

    cat <<-EOF > $cmdfile
    aws cloudformation $action \\
      --stack-name ${FULL_STACK_NAME} \\
      $([ $task == 'update-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/rds-oracle.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'VpcId' 'VPC_ID'
    add_parameter $cmdfile 'TemplateBucketName' 'TEMPLATE_BUCKET_NAME'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'DBInstanceClass' 'DB_INSTANCE_CLASS'
    add_parameter $cmdfile 'MultiAZ' 'MULTI_AZ'
    add_parameter $cmdfile 'Engine' 'ENGINE'
    add_parameter $cmdfile 'DBName' 'DB_NAME'
    add_parameter $cmdfile 'Port' 'PORT'
    add_parameter $cmdfile 'LicenseModel' 'LICENSE_MODEL'
    add_parameter $cmdfile 'AllocatedStorage' 'ALLOCATED_STORAGE'
    add_parameter $cmdfile 'AutoMinorVersionUpgrade' 'AUTO_MINOR_VERSION_UPGRADE'
    add_parameter $cmdfile 'BackupRetentionPeriod' 'BACKUP_RETENTION_PERIOD'
    add_parameter $cmdfile 'CharacterSetName' 'CHARACTERSET_NAME'
    add_parameter $cmdfile 'Iops' 'IOPS'
    add_parameter $cmdfile 'JumpboxInstanceType' 'JUMPBOX_INSTANCE_TYPE'
    if [ -n "$APP_SECURITY_GROUP_ID" ] ; then
      add_parameter $cmdfile 'ApplicationSecurityGroupId' 'APP_SECURITY_GROUP_ID'
    else
      add_parameter $cmdfile 'CampusSubnetCIDR1' 'CAMPUS_SUBNET1_CIDR'
      add_parameter $cmdfile 'CampusSubnetCIDR2' 'CAMPUS_SUBNET2_CIDR'
    fi

    if [ "${USING_ROUTE53,,}" == 'true' ] ; then
      # HOSTED_ZONE_NAME="$(getHostedZoneNameByLandscape $LANDSCAPE)"
      # [ -z "$HOSTED_ZONE_NAME" ] && echo "ERROR! Cannot acquire hosted zone name. Cancelling..." && exit 1
      # add_parameter $cmdfile 'HostedZoneName' 'HOSTED_ZONE_NAME'
      [ -z "$(getHostedZoneId $HOSTED_ZONE)" ] && echo "ERROR! Cannot detect hosted zone for $HOSTED_ZONE" && exit 1
      addParameter $cmdfile 'HostedZoneName' $HOSTED_ZONE
    fi

    checkLandscapeParameters

    checkRDSParameters

    add_parameter $cmdfile 'Baseline' 'BASELINE'

    processRdsParameters $cmdfile $LANDSCAPE "$RDS_SNAPSHOT_ARN" "$RDS_ARN_TO_CLONE"

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'database'
    addTag $cmdfile 'Subcategory' 'oracle'
    echo "      ]'" >> $cmdfile

    runStackActionCommand

  fi
}

runTask() {
  case "$task" in
    validate)
      validateStack silent ;;
    upload)
      uploadStack ;;
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
    delete-stack)
      stackAction "delete-stack" ;;
    get-password)
      # Must include PROFILE and LANDSCAPE/BASELINE
      local landscape="$BASELINE"
      [ -z "$landscape" ] && landscape="$LANDSCAPE"
      getDbPassword 'admin' "$landscape" ;;
    set-rds-access)
      refreshRdsIngress $LANDSCAPE ;;
    test)
      LANDSCAPE=sb
      checkSubnetsInLegacyAccount ;;
      # waitForStackToDelete ;;
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