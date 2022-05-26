declare -A defaults=(
  [STACK_NAME]='kuali-shutdown'
  [CODE_BUCKET_NAME]='shutdown-scheduler'
  [CODE_BUCKET_PATH]='shutdown-scheduler.zip'
  [SERVICE]='research-administration'
  [FUNCTION]='kuali'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_shutdown" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the kuali_shutdown subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    checkLegacyAccount

    setDefaults

    validateParms
  fi

  runTask
}

validateParms() {
  local interval=${MINUTE_INTERVAL:-'5'}
  interval=$(($interval*60));
  local timeout=${LAMBDA_TIMEOUT:-'60'}
  if [ $timeout -gt $interval ] ; then
    echo "The lambda timeout cannot be greater than the minute interval"
    exit 1
  fi
  GLOBAL_TAG=${GLOBAL_TAG:-$STACK_NAME}
}

stackAction() {
  local action=$1   

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $STACK_NAME
    if ! waitForStackToDelete ; then
      echo "Problem deleting stack!"
      exit 1
    fi
  else

    # Validate the yaml file(s)
    outputHeading "Validating main template(s)..."
    validateStack silent=true filepath=../lambda/shutdown_scheduler/shutdown.yaml
    [ $? -gt 0 ] && exit 1

    # Upload lambda code
    if [ "$PACKAGE_JAVASCRIPT" != 'false' ] ; then
      outputHeading "Building, zipping, and uploading lambda code..."
      if ! bucketExistsInThisAccount "$CODE_BUCKET_NAME" ; then
        if askYesNo "The bucket $CODE_BUCKET_NAME does not exist create it?" ; then
          aws s3 mb s3://$CODE_BUCKET_NAME
          [ $? -gt 0 ] && echo "ERROR! Could not create bucket s3://$CODE_BUCKET_NAME, Cancelling..." && exit 1
        else
          echo "Cancelling..."
          exit 0
        fi
      fi
      local zipfile=s3://$CODE_BUCKET_NAME/$CODE_BUCKET_PATH
      if [ "${SKIP_BUILD,,}" != 'true' ] ; then
        zipPackageAndCopyToS3 '../lambda/shutdown_scheduler' "$zipfile"
        [ $? -gt 0 ] && echo "ERROR! Could not upload shutdown_scheduler.zip to s3 at $zipfile" && exit 1
      fi
    fi

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-body "file://../lambda/shutdown_scheduler/shutdown.yaml" \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'Service' 'SERVICE'
    add_parameter $cmdfile 'Function' 'FUNCTION'
    add_parameter $cmdfile 'CodeBucketName' 'CODE_BUCKET_NAME'
    add_parameter $cmdfile 'CodeBucketPath' 'CODE_BUCKET_PATH'
    add_parameter $cmdfile 'StartupCronKey' 'STARTUP_CRON_KEY'
    add_parameter $cmdfile 'ShutdownCronKey' 'SHUTDOWN_CRON_KEY'
    add_parameter $cmdfile 'RebootCronKey' 'REBOOT_CRON_KEY'
    add_parameter $cmdfile 'LastRebootTimeKey' 'LAST_REBOOT_TIME_KEY'
    add_parameter $cmdfile 'MinuteInterval' 'MINUTE_INTERVAL'
    add_parameter $cmdfile 'LambdaTimeout' 'LAMBDA_TIMEOUT'

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'application'
    addTag $cmdfile 'Subcategory' 'lambda'
    echo "      ]'" >> $cmdfile

    runStackActionCommand
  fi
}

runTask() {
  case "$task" in
    validate)
      validateStack filepath;;
    upload)
      uploadStack ;;
    create-stack)
      stackAction "create-stack" ;;
    recreate-stack)
      PROMPT='false'
      task='delete-stack'
      stackAction "delete-stack" 2> /dev/null
      task='create-stack'
      stackAction "create-stack"
      ;;
    update-stack)
      stackAction "update-stack" ;;
    reupdate-stack)
      PROMPT='false'
      task='update-stack'
      stackAction "update-stack" ;;
    delete-stack)
      stackAction "delete-stack" ;;
    test)
      echo "No test configured yet." ;;
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