#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-dms-oracle'
  [GLOBAL_TAG]='kuali-dms-oracle'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
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
    # Upload the yaml file(s) to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws cloudformation $action \\
      --stack-name ${STACK_NAME}-${LANDSCAPE} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/dms.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    addParameter $cmdfile 'VpcId' $VpcId

    [ -n "$LANDSCAPE" ] && \
      addParameter $cmdfile 'Landscape' $LANDSCAPE
    [ -n "$GLOBAL_TAG" ] && \
      addParameter $cmdfile 'GlobalTag' $GLOBAL_TAG
    [ -n "$MULTI_AZ" ] && \
      addParameter $cmdfile 'MultiAZ' $MULTI_AZ
    [ -n "$DB_NAME" ] && \
      addParameter $cmdfile 'DBName' $DB_NAME
    [ -n "$MASTER_USERNAME" ] && \
      addParameter $cmdfile 'MasterUsername' $MASTER_USERNAME
    [ -n "$DB_PORT" ] && \
      addParameter $cmdfile 'DBPort' $DB_PORT

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
    migrate)
      migrate ;;
    test)
      echo "testing" ;;
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