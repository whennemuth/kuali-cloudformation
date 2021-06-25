declare -A defaults=(
  [STACK_NAME]='kuali-shutdown'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_shutdown'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_shutdown" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the kuali_ecs subdirectory!."
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

    # Validate and upload the yaml file(s) to s3
    outputHeading "Validating and uploading main template(s)..."
    validateTemplateAndUploadToS3 \
      silent=true \
      filepath=../lambda/shutdown_scheduler/shutdown.yaml \
      s3path=$TEMPLATE_BUCKET_PATH/
    [ $? -gt 0 ] && exit 1

    # Upload lambda code
    if [ "$PACKAGE_JAVASCRIPT" != 'false' ] ; then
      outputHeading "Building, zipping, and uploading lambda code..."
      zipPackageAndCopyToS3 '../lambda/shutdown_scheduler' "s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_lambda/shutdown_scheduler.zip"
      [ $? -gt 0 ] && echo "ERROR! Could not upload shutdown_scheduler.zip to s3." && exit 1
    fi

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/shutdown.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'TemplateBucketName' 'TEMPLATE_BUCKET_NAME'
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