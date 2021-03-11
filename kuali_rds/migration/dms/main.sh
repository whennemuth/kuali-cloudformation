#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-dms-oracle'
  [GLOBAL_TAG]='kuali-dms-oracle'
  [LANDSCAPE]='sb'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # [MULTI_AZ]=['???']
  # [VPC_ID]=['???']
  # [MASTER_USERNAME]=['???']
  # [DB_NAME]=['???']
  # [DB_PORT]=['???']
  # [REPLICATION_INSTANCE_ID]=['???']
  # [SOURCE_SUBNET_ID]=['???']
  # [TARGET_SUBNET_ID]=['???']
  # [SOURCE_SECURITY_GROUP]=['???']
  # [TARGET_SECURITY_GROUP]=['???']
  # [REPLICATION_INSTANCE_ALLOCATION_STORAGE]=['???']
)


run() {
  source ../../../scripts/common-functions.sh

  if ! isCurrentDir 'dms' ; then
    echo "You must run this script from the dms (database migration service) subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if ! isBuCloudInfAccount ; then
    LEGACY_ACCOUNT='true'
    echo 'Current profile indicates legacy account.'
    defaults['TEMPLATE_BUCKET_PATH']='s3://kuali-research-ec2-setup/cloudformation/kuali_rds/migration/dms'
  fi

  if [ "$task" == "test" ] ; then
    SILENT='true'
    [ -z "$PROFILE" ] && PROFILE='default'
  fi

  parseArgs $@

  setDefaults

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
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws cloudformation $action \\
      --stack-name ${FULL_STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/dms.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF
    
    # Get db connection fields directly from kc-config.xml in s3 for those source db parameters that are empty.
    # local counter=1
    # while read dbParm ; do
    #   case $counter in
    #     2) [ -z "$SOURCE_DB_SERVER_NAME" ] && SOURCE_DB_SERVER_NAME="$dbParm" ;;
    #     3) [ -z "$SOURCE_DB_NAME" ] && SOURCE_DB_NAME="$dbParm" ;;
    #     4) [ -z "$SOURCE_DB_PORT" ] && SOURCE_DB_PORT="$dbParm" ;;
    #     6) [ -z "$SOURCE_DB_USER_NAME" ] && SOURCE_DB_USER_NAME="$dbParm" ;;
    #     7) [ -z "$SOURCE_DB_PASSWORD" ] && SOURCE_DB_PASSWORD="$dbParm" ;;
    #   esac
    #   ((counter++))
    # done <<< $(getKcConfigDb)
    # [ -z "$SOURCE_DB_PASSWORD" ] && echo "Missing parameter: SOURCE_DB_PASSWORD" && exit 1
    # [ -z "$SOURCE_DB_SERVER_NAME" ] && echo "Missing parameter: SOURCE_DB_SERVER_NAME" && exit 1
    [ -z "$PRIVATE_SUBNET1" ] && echo "Missing parameter: PRIVATE_SUBNET1" && exit 1
    [ -z "$PRIVATE_SUBNET1_AZ" ] && echo "Missing parameter: PRIVATE_SUBNET1_AZ" && exit 1
    [ -z "$PRIVATE_SUBNET2" ] && echo "Missing parameter: PRIVATE_SUBNET2" && exit 1

    add_parameter $cmdfile 'SubnetId1' 'PRIVATE_SUBNET1'
    add_parameter $cmdfile 'SubnetId2' 'PRIVATE_SUBNET2'

    add_parameter $cmdfile 'SourceDbEngine' 'SOURCE_DB_ENGINE'
    add_parameter $cmdfile 'SourceSecurityGroup' 'SOURCE_SECURITY_GROUP'
    # add_parameter $cmdfile 'SourceDbPassword' 'SOURCE_DB_PASSWORD'
    # add_parameter $cmdfile 'SourceDbName' 'SOURCE_DB_NAME'
    # add_parameter $cmdfile 'SourceDbUsername' 'SOURCE_DB_USER_NAME'
    # add_parameter $cmdfile 'SourceDbServerName' 'SOURCE_DB_SERVER_NAME'
    # add_parameter $cmdfile 'SourceDbPort' 'SOURCE_DB_PORT'

    add_parameter $cmdfile 'TargetDbName' 'TARGET_DB_NAME'
    add_parameter $cmdfile 'TargetDbEngine' 'TARGET_DB_ENGINE'
    add_parameter $cmdfile 'TargetDbPort' 'TARGET_DB_PORT'
    add_parameter $cmdfile 'TargetSecurityGroup' 'TARGET_SECURITY_GROUP'

    add_parameter $cmdfile 'VpcId' 'VPC_ID'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'ReplicationInstanceAZ' 'PRIVATE_SUBNET1_AZ'
    add_parameter $cmdfile 'ReplicationInstanceAllocatedStorage' 'REPLICATION_INSTANCE_ALLOCATION_STORAGE'
    add_parameter $cmdfile 'ReplicationInstanceClass' 'REPLICATION_INSTANCE_CLASS'
    add_parameter $cmdfile 'DbSchemaName' 'DB_SCHEMA_NAME'
    add_parameter $cmdfile 'MigrationType' 'MIGRATION_TYPE'
    add_parameter $cmdfile 'TargetTablePrepMode' 'TARGET_TABLE_PREP_MODE'
    add_parameter $cmdfile 'EnableLogging' 'ENABLE_LOGGING'
    add_parameter $cmdfile 'EnableValidation' 'ENABLE_VALIDATION'
    add_parameter $cmdfile 'ValidationOnly' 'VALIDATION_ONLY'
    add_parameter $cmdfile 'RecoverableErrorCount' 'RECOVERABLE_ERROR_COUNT'
    add_parameter $cmdfile 'FailOnTransactionConsistencyBreached' 'FAIL_ON_TRANSACTION_CONSISTENCY_BREACHED'

    if [ -z "$TARGET_DB_SERVER_NAME" ] ; then
      TARGET_DB_SERVER_NAME=$(getRdsHostname)
    fi
    [ -z "$TARGET_DB_SERVER_NAME" ] && echo "Missing parameter: TARGET_DB_SERVER_NAME" && exit 1
    add_parameter $cmdfile 'TargetDbServerName' 'TARGET_DB_SERVER_NAME'

    echo "      ]'" >> $cmdfile

    runStackActionCommand

  fi
}

# Repeat calls for connection test status until a failure or success indication is returned.
connectSuccess() {
  local counter=1
  local status="unknown"
  local endpointArn="$1"

  while true ; do
    status="$(
      aws dms describe-connections \
        --filters Name=endpoint-arn,Values=$endpointArn \
        --output text \
        --query 'Connections[].{status:Status}' 2> /dev/null
    )"
    [ -z "$status" ] && status='unknown' && break
    [ "${status,,}" != 'testing' ] && break
    echo "$endpointArn connection status check $counter: $status"
    ((counter++))
    sleep 3
  done

  echo "$endpointArn connection status check $counter: $status"
  [ "${status,,}" == 'successful' ] && true || false
}

# Test both the source and target endpoints for database connection success.
# If either one of them fails, the overall result is false, else true.
connectionsOk() {
  while read line ; do
    local evalstr="$(echo "$line" | awk '{print $1}')=$(echo "$line" | awk '{print $2}')"
    echo "$evalstr"
    eval "$evalstr"
  done <<< $(aws cloudformation describe-stacks \
    --stack-name kuali-dms-oracle-ci \
    --output text \
    --query 'Stacks[].Outputs[].{key:OutputKey,val:OutputValue}'
  )

  local endpointsOk='true' # Assume success and go on to prove.
  aws dms test-connection --replication-instance-arn "$ReplicationInstance" --endpoint-arn "$DmsEndpointSource"
  if ! connectSuccess $DmsEndpointSource ; then
    endpointsOk='false'
    if ! askYesNo "Source connection test failed. Test target connection?" ; then
      return 1
    fi
  fi

  aws dms test-connection --replication-instance-arn "$ReplicationInstance" --endpoint-arn "$DmsEndpointTarget"
  if ! connectSuccess $DmsEndpointTarget ; then
    endpointsOk='false'
  fi

  [ "$endpointsOk" == 'true' ] && true || false
}

# Perform a pre-migration assessment test, preceded by an endpoint database connection test.
preMigrationAssessmentOk() {
  if connectionsOk ; then
    aws dms start-replication-task-assessment --replication-task-arn "$DmsReplicationTask"
    local counter=1
    local status="unknown"

    while true ; do
      status="$(
        aws dms describe-replication-task-assessment-results \
          --replication-task-arn $DmsReplicationTask \
          --output text \
          --query 'ReplicationTaskAssessmentResults[].{status:AssessmentStatus}' 2> /dev/null
      )"
      [ -z "$status" ] && status='unknown' && break
      [ "${status,,}" != 'in progress' ] && break
      echo "Task assessment status check $counter: $status"
      ((counter++))
      sleep 3
    done

    echo "Task assessment status check $counter: $status"

    local results=$(curl "$(aws dms describe-replication-task-assessment-results \
      --replication-task-arn $DmsReplicationTask \
      --output text \
      --query 'ReplicationTaskAssessmentResults[].{s3obj:S3ObjectUrl}' 2> /dev/null
    )")
    if jqInstalled ; then
      echo "$results" | jq '.'
    fi

    [ "${status,,}" == 'no issues found' ] && true || false

  else 
    echo "Cannot perform pre-migration assessment due to source and/or target endpoint database connection failure."
    exit 1
  fi
}

migrate() {
  local taskType="${1:-"start-replication"}"
  local arn=$(
    aws dms describe-replication-tasks \
      --filter Name=replication-task-id,Values=${GLOBAL_TAG}-${LANDSCAPE}-dms-replication-task \
      --output text \
      --query 'ReplicationTasks[].{arn:ReplicationTaskArn}' 2> /dev/null
  )
  ([ -z "$arn" ] || [ "${arn,,}" == 'none' ]) && echo "ERROR! Cannot acquire replication task arn." && exit 1

  aws dms start-replication-task \
    --replication-task-arn $arn \
    --start-replication-task-type $taskType
}

runTask() {
  case "$task" in
    migrate)
      migrate $TASK_TYPE ;;
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
    test-connections)
      connectionsOk ;;
    pre-migration-assessment)
      preMigrationAssessmentOk ;;
    get-password)
      # Must include PROFILE and LANDSCAPE
      getRdsAdminPassword ;;
    test)
      LANDSCAPE='ci'
      # local counter=1
      # while read line ; do
      #   echo "$counter) $line"
      #   ((counter++))
      # done <<<$(getKcConfigDb)
      checkSubnetsInLegacyAccount
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