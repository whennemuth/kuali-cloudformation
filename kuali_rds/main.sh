#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-rds-oracle'
  [GLOBAL_TAG]='kuali-oracle'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  [ENGINE]='oracle-se2'
  [MAJOR_VERSION]='19'
  # ----- Some of the following are defaulted in the yaml file itself:
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

  if [ "$task" != "test" ] ; then
    parseArgs $@
  fi

  runTask
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name ${STACK_NAME}-${LANDSCAPE}
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
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
      --template-url $BUCKET_URL/oracle.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $VpcId
    addParameter $cmdfile 'CampusSubnetCIDR1' $CAMPUS_SUBNET1_CIDR
    addParameter $cmdfile 'CampusSubnetCIDR2' $CAMPUS_SUBNET2_CIDR
    addParameter $cmdfile 'DBSubnet1' $PRIVATE_SUBNET1
    addParameter $cmdfile 'DBSubnet2' $PRIVATE_SUBNET2
    addParameter $cmdfile 'DBSubnetCIDR1' $PRIVATE_SUBNET1_CIDR
    addParameter $cmdfile 'DBSubnetCIDR2' $PRIVATE_SUBNET2_CIDR

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

    if [ -z "$ENGINE_VERSION" ] ; then
      ENGINE_VERSION="$(getOracleEngineVersion $ENGINE $MAJOR_VERSION)"
      if [ -z "$ENGINE_VERSION" ] && [ "$action" == "create-stack" ] ; then
        echo "ERROR! Cannot determine engine version"
        exit 1
      fi
    fi
    addParameter $cmdfile 'EngineVersion' $ENGINE_VERSION

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
    create-stack)
      stackAction "create-stack" ;;
    update-stack)
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
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