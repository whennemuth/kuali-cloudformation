#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-rds-oracle'
  [GLOBAL_TAG]='kuali-oracle'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [ENGINE]='oracle-se2'
  [MAJOR_VERSION]='19'
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
  # [DB_SNAPSHOT_ARN]='???'
  # [AUTO_MINOR_VERSION_UPGRADE]='???'
  # [BACKUP_RETENTION_PERIOD]='???'
  # [CHARACTERSET_NAME]='???'
  # [IOPS]='???'
  # [JUMPBOX_INSTANCE_TYPE]='???'
)


run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_rds" ; then
    echo "You must run this script from the kuali_rds subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" == 'get-password' ] ; then
    # Operate silently so that only the password shows up without the extra console output.
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

    checkLandscapeParameters

    checkRDSParameters    # Based on landscape and other parameters, perform rds cloning if indicated.

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
    add_parameter $cmdfile 'CampusSubnetCIDR1' 'CAMPUS_SUBNET1_CIDR'
    add_parameter $cmdfile 'CampusSubnetCIDR2' 'CAMPUS_SUBNET2_CIDR'
    add_parameter $cmdfile 'DBSubnet1' 'PRIVATE_SUBNET1'
    add_parameter $cmdfile 'DBSubnet2' 'PRIVATE_SUBNET2'
    add_parameter $cmdfile 'DBSubnetCIDR1' 'PRIVATE_SUBNET1_CIDR'
    add_parameter $cmdfile 'DBSubnetCIDR2' 'PRIVATE_SUBNET2_CIDR'
    add_parameter $cmdfile 'TemplateBucketName' 'TEMPLATE_BUCKET_NAME'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'Baseline' 'BASELINE'
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
      
    if [ -z "$ENGINE_VERSION" ] ; then
      ENGINE_VERSION="$(getOracleEngineVersion $ENGINE $MAJOR_VERSION)"
      if [ -z "$ENGINE_VERSION" ] && [ "$action" == "create-stack" ] ; then
        echo "ERROR! Cannot determine rds engine version"
        exit 1
      fi
    fi
    add_parameter $cmdfile 'EngineVersion' 'ENGINE_VERSION'

    # The rds instance might be intended to be based on a snapshot.
    if [ -n "$DB_SNAPSHOT_ARN" ] ; then
      if [ "${DB_SNAPSHOT_ARN,,}" == 'latest' ] ; then
        DB_SNAPSHOT_ARN="$(getLatestRdsSnapshotArn)"
        [ -z "$DB_SNAPSHOT_ARN" ] && echo "ERROR! Cannot find latest RDS snapshot ARN" && exit 1
      fi
      add_parameter $cmdfile 'DBSnapshotARN' 'DB_SNAPSHOT_ARN'
    fi

      # AVAILABILITY ZONE: 
      # 1) 
      #   An rds instance must have a subnet group that includes at least two subnets in at least two availability zones.
      #   This requirement exists even for single-az deployments. AWS documentation states that this is to allow for a change 
      #   of heart where one wants to convert the existing single-az to a mulit-az deployment.
      #   If multi-az is false, we want to specify our preferred of the two availability zones. This is done by
      #   setting the "AvailabilityZone" property of the rds instance. In our case it will be the availability zone of the first
      #   of the two subnets in the database subnet group. When deployment is complete, the rds instance should have a private
      #   ip address that falls within the cidr block of the first subnet.
      # 2)
      #   If multi-az is true, then the "AvailabilityZone" property becomes an illegal setting and will cause an error.
    if [ "$MULTI_AZ" != 'true' ] ; then
      add_parameter $cmdfile 'AvailabilityZone' 'PRIVATE_SUBNET1_AZ'
      if [ -z "$PRIVATE_SUBNET1_AZ" ] ; then
        echo "ERROR! Single-AZ deployment indicated, but the availability zone of the first subnet in the database subnet group cannot be determined."
        exit 1
      fi
    fi

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
      validateStack silent;;
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
      # Must include PROFILE and LANDSCAPE
      getRdsAdminPassword ;;
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