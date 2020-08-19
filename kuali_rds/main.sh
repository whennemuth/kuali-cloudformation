#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-rds-oracle'
  [GLOBAL_TAG]='kuali-oracle'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [ENGINE]='oracle-se2'
  [MAJOR_VERSION]='19'
  # ----- Some of the following are defaulted in the yaml file itself:
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

  if [ "$task" == 'create-stack' ] || [ "$task" == 'update-stack' ] ; then
    if ! isBuCloudInfAccount ; then
      LEGACY_ACCOUNT='true'
      echo 'Current profile indicates legacy account.'
      defaults['BUCKET_PATH']='s3://kuali-research-ec2-setup/cloudformation/kuali_rds'
    fi
  fi

  if [ "$task" != "test" ] ; then

    parseArgs $@

    setDefaults
  fi

  runTask $@
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name ${STACK_NAME}-${LANDSCAPE}
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
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws cloudformation $action \\
      --stack-name ${STACK_NAME}-${LANDSCAPE} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/rds-oracle.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $VpcId
    addParameter $cmdfile 'CampusSubnetCIDR1' $CAMPUS_SUBNET1_CIDR
    addParameter $cmdfile 'DBSubnet1' $PRIVATE_SUBNET1
    addParameter $cmdfile 'DBSubnet2' $PRIVATE_SUBNET2
    addParameter $cmdfile 'DBSubnetCIDR1' $PRIVATE_SUBNET1_CIDR
    addParameter $cmdfile 'DBSubnetCIDR2' $PRIVATE_SUBNET2_CIDR

    [ -n "$BUCKET_NAME" ] && \
      addParameter $cmdfile 'BucketName' $BUCKET_NAME
    [ -n "$LANDSCAPE" ] && \
      addParameter $cmdfile 'Landscape' $LANDSCAPE
    [ -n "$GLOBAL_TAG" ] && \
      addParameter $cmdfile 'GlobalTag' $GLOBAL_TAG
    [ -n "$DB_INSTANCE_CLASS" ] && \
      addParameter $cmdfile 'DBInstanceClass' $DB_INSTANCE_CLASS
    [ -n "$MULTI_AZ" ] && \
      addParameter $cmdfile 'MultiAZ' $MULTI_AZ
    [ -n "$ENGINE" ] && \
      addParameter $cmdfile 'Engine' $ENGINE
    [ -n "$DB_NAME" ] && \
      addParameter $cmdfile 'DBName' $DB_NAME
    [ -n "$MASTER_USERNAME" ] && \
      addParameter $cmdfile 'MasterUsername' $MASTER_USERNAME
    [ -n "$PORT" ] && \
      addParameter $cmdfile 'Port' $PORT
    [ -n "$LICENSE_MODEL" ] && \
      addParameter $cmdfile 'LicenseModel' $LICENSE_MODEL
    [ -n "$ALLOCATED_STORAGE" ] && \
      addParameter $cmdfile 'AllocatedStorage' $ALLOCATED_STORAGE
    [ -n "$DB_SNAPSHOT_ARN" ] && \
      addParameter $cmdfile 'DBSnapshotARN' $DB_SNAPSHOT_ARN
    [ -n "$AUTO_MINOR_VERSION_UPGRADE" ] && \
      addParameter $cmdfile 'AutoMinorVersionUpgrade' $AUTO_MINOR_VERSION_UPGRADE
    [ -n "$BACKUP_RETENTION_PERIOD" ] && \
      addParameter $cmdfile 'BackupRetentionPeriod' $BACKUP_RETENTION_PERIOD
    [ -n "$CHARACTERSET_NAME" ] && \
      addParameter $cmdfile 'CharacterSetName' $CHARACTERSET_NAME
    [ -n "$IOPS" ] && \
      addParameter $cmdfile 'Iops' $IOPS
    [ -n "$JUMPBOX_INSTANCE_TYPE" ] && \
      addParameter $cmdfile 'JumpboxInstanceType' $JUMPBOX_INSTANCE_TYPE

    if [ -n "$CAMPUS_SUBNET2_CIDR" ] ; then
      addParameter $cmdfile 'CampusSubnetCIDR2' $CAMPUS_SUBNET2_CIDR
    else
      addParameter $cmdfile 'CampusSubnetCIDR2' $CAMPUS_SUBNET1_CIDR
    fi

    if [ -z "$ENGINE_VERSION" ] ; then
      ENGINE_VERSION="$(getOracleEngineVersion $ENGINE $MAJOR_VERSION)"
      if [ -z "$ENGINE_VERSION" ] && [ "$action" == "create-stack" ] ; then
        echo "ERROR! Cannot determine engine version"
        exit 1
      fi
    fi
    addParameter $cmdfile 'EngineVersion' $ENGINE_VERSION

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
      if [ -n "$PRIVATE_SUBNET1_AZ" ] ; then
        addParameter $cmdfile 'AvailabilityZone' $PRIVATE_SUBNET1_AZ
      else
        echo "ERROR! Single-AZ deployment indicated, but the availability zone of the first subnet in the database subnet group cannot be determined."
        exit 1
      fi
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


# We are running against the "Legacy" kuali aws account, so an adapted version of checkSubnets is needed.
# -------------------------------------------------------------------------------------------------------
# Ensure that there are 4 subnets are specified (2 application subnets and 2 database subnets).
# If any are not provided, then look them up with the cli against their tags and assign them accordingingly.
# If any are provided, look them up to validate that they exist as subnets.
checkSubnetsInLegacyAccount() {
  # Clear out the last command file
  printf "" > $cmdfile

  getSubnets \
    'CAMPUS_SUBNET' \
    'Name=tag:Network,Values=application' \
    'Name=tag:Environment,Values='$LANDSCAPE

  getSubnets \
    'PRIVATE_SUBNET' \
    'Name=tag:Network,Values=database' \
    'Name=tag:Environment,Values='$LANDSCAPE

  getSubnets \
    'PRIVATE_SUBNET' \
    'Name=tag:Network,Values=database' \
    'Name=tag:Environment2,Values='$LANDSCAPE

  source ./$cmdfile

  # Count how many application subnets have values
  local appSubnets=$(grep -P 'CAMPUS_SUBNET\d=' $cmdfile | wc -l)
  if [ $appSubnets -lt 2 ] ; then
    # Some subnets might have been explicitly provided by the user as a parameter, but look those up to verify they exist.
    if [ -z "$(grep 'CAMPUS_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET1" && ((appSubnets++)) && echo "CAMPUS_SUBNET1=$CAMPUS_SUBNET1"
    fi
    if [ -z "$(grep 'CAMPUS_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET2" && ((appSubnets++)) && echo "CAMPUS_SUBNET2=$CAMPUS_SUBNET2"
    fi
    # We can have less than two application subnets, but must have at least one.
  fi

  # Count how many database subnets have values
  local dbSubnets=$(grep -P 'PRIVATE_SUBNET\d=' $cmdfile | wc -l)
  if [ $dbSubnets -lt 2 ] ; then
    # Some subnets might have been explicitly provided by the user as a parameter, but look those up to verify they exist.
    if [ -z "$(grep 'PRIVATE_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET1" && ((dbSubnets++)) && echo "PRIVATE_SUBNET1=$PRIVATE_SUBNET1"
    fi    
    if [ -z "$(grep 'PRIVATE_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET2" && ((dbSubnets++)) && echo "PRIVATE_SUBNET2=$PRIVATE_SUBNET2"
    fi    
    # If we still don't have a total of 2 or more database subnets then exit with an error code
  fi

  cat ./$cmdfile
  source ./$cmdfile

  [ $appSubnets -lt 1 ] && echo "ERROR! Must have at least one application subnet \nNone are provided and could not be found with cli."
  [ $dbSubnets -lt 2 ] && echo "ERROR! Must have 2 database subnets \n1 or more are missing and could not be found with cli."
  [ $((appSubnets+dbSubnets)) -lt 3 ] && false || true
}

runTask() {
  case "$task" in
    validate)
      validateStack silent;;
    upload)
      uploadStack ;;
    create-stack)
      stackAction "create-stack" ;;
    update-stack)
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
    test)
      # export AWS_PROFILE=infnprd
      # PROFILE=infnprd
      LANDSCAPE=sb
      checkSubnetsInLegacyAccount ;;
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