#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-secrets'
  [GLOBAL_TAG]='kuali-secrets'
  [LANDSCAPE]='sb'
  [BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_rds'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # [RDS_APP_USERNAME]='???'
  # [RDS_APP_PASSWORD]='???'
  # [EC2_DB_APP_PASSWORD]='???'
  # [EC2_DB_HOST]='???'
  # [EC2_DB_SID]='???'
  # [EC2_DB_PORT]='???'
  # [EC2_DB_APP_USERNAME]='???'
  # [EC2_DB_DMS_USERNAME]='???'
  # [EC2_DB_DMS_PASSWORD]='???'
  # [EC2_DB_SCT_USERNAME]='???'
  # [EC2_DB_SCT_PASSWORD]='???'
)


run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir 'kuali_secrets' ; then
    echo "You must run this script from the root (kuali_secrets) directory!"
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" == "test" ] ; then
    SILENT='true'
    [ -z "$PROFILE" ] && PROFILE='default'
  fi

  parseArgs $@

  if ! isBuCloudInfAccount ; then
    LEGACY_ACCOUNT='true'
    echo 'Current profile indicates legacy account.'
    defaults['BUCKET_PATH']='s3://kuali-research-ec2-setup/cloudformation/kuali_secrets'
  fi

  setDefaults

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
      --template-url $BUCKET_URL/secrets.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'RdsAppPassword' 'RDS_APP_PASSWORD'

    if [ "$LEGACY_ACCOUNT" == true ] ; then
      # Get "LEGACY" ec2 kuali db connection fields directly from kc-config.xml in s3 for those source db parameters that are empty.
      local counter=1
      while read dbParm ; do
        case $counter in
          1) [ -z "$EC2_DB_APP_PASSWORD" ] && EC2_DB_APP_PASSWORD="$dbParm" ;;
          2) [ -z "$EC2_DB_HOST" ] && EC2_DB_HOST="$dbParm" ;;
          3) [ -z "$EC2_DB_SID" ] && EC2_DB_SID="$dbParm" ;;
          4) [ -z "$EC2_DB_PORT" ] && EC2_DB_PORT="$dbParm" ;;
          5) [ -z "$EC2_DB_APP_USERNAME" ] && EC2_DB_APP_USERNAME="$dbParm" ;;
          6) [ -z "$EC2_DB_DMS_USERNAME" ] && EC2_DB_DMS_USERNAME="$dbParm" ;;
          7) [ -z "$EC2_DB_DMS_PASSWORD" ] && EC2_DB_DMS_PASSWORD="$dbParm" ;;
          8) [ -z "$EC2_DB_SCT_USERNAME" ] && EC2_DB_SCT_USERNAME="$dbParm" ;;
          9) [ -z "$EC2_DB_SCT_PASSWORD" ] && EC2_DB_SCT_PASSWORD="$dbParm" ;;
        esac
        ((counter++))
      done <<< $(getKcConfigDb)

      add_parameter $cmdfile 'Ec2DbHost' 'EC2_DB_HOST'
      add_parameter $cmdfile 'Ec2DbSid' 'EC2_DB_SID'
      add_parameter $cmdfile 'Ec2DbPort' 'EC2_DB_PORT'
      add_parameter $cmdfile 'Ec2DbAppUsername' 'EC2_DB_APP_USERNAME'
      add_parameter $cmdfile 'Ec2DbAppPassword' 'EC2_DB_APP_PASSWORD'
      add_parameter $cmdfile 'Ec2DbDmsUsername' 'EC2_DB_DMS_USERNAME'
      add_parameter $cmdfile 'Ec2DbDmsPassword' 'EC2_DB_DMS_PASSWORD'
      add_parameter $cmdfile 'Ec2DbSctUsername' 'EC2_DB_SCT_USERNAME'
      add_parameter $cmdfile 'Ec2DbSctPassword' 'EC2_DB_SCT_PASSWORD'
    fi

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