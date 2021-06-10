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
  if [ -n "$CRON_EXPRESION" ] ; then
    local minutes="$(echo "$CRON_EXPRESSION" | cut -d' ' -f1 | grep -oP '\d')"
    [ -z "$minutes" ] && minutes='1'
    local interval=$(($minutes*60));
    local timeout=$LAMBDA_TIMEOUT
    [ -z "$timeout" ] && timeout='60'
    if [ $timeout -gt $interval ] ; then
      echo "The lambda timeout cannot be greater than the interval indicated by the cron expression"
      exit 1
    fi
  fi

  for i in {1..5} ; do
    eval 'local key=$TAG_KEY'$i
    eval 'local val=$TAG_VAL'$i
    if [ -n "$key" ] && [ -z "$val" ] ; then
      echo "TAG_KEY${i}: $key has no value!"
      exit 1
    fi
  done
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
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    # Upload lambda code
    outputHeading "Building, zipping, and uploading lambda code..."
    zipPackageAndCopyToS3 '../lambda/shutdown_scheduler' 's3://kuali-conf/cloudformation/kuali_lambda/shutdown_scheduler.zip'
    [ $? -gt 0 ] && echo "ERROR! Could not upload shutdown_scheduler.zip to s3." && exit 1

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/main.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'TagKey1' 'TAG_KEY1'
    add_parameter $cmdfile 'TagKey2' 'TAG_KEY2'
    add_parameter $cmdfile 'TagKey3' 'TAG_KEY3'
    add_parameter $cmdfile 'TagKey4' 'TAG_KEY4'
    add_parameter $cmdfile 'TagKey5' 'TAG_KEY5'

    add_parameter $cmdfile 'TagVal1' 'TAG_VAL1'
    add_parameter $cmdfile 'TagVal2' 'TAG_VAL2'
    add_parameter $cmdfile 'TagVal3' 'TAG_VAL3'
    add_parameter $cmdfile 'TagVal4' 'TAG_VAL4'
    add_parameter $cmdfile 'TagVal5' 'TAG_VAL5'

    add_parameter $cmdfile 'StartupCronKey' 'STARTUP_CRON_KEY'
    add_parameter $cmdfile 'ShutdownCronKey' 'SHUTDOWN_CRON_KEY'
    add_parameter $cmdfile 'CronExpression' 'CRON_EXPRESSION'
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
      validateStack ;;
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