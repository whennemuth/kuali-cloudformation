declare TEMPLATE_BUCKET=${TEMPLATE_BUCKET:-"kuali-conf"}
declare -A defaults=(
  [STACK_NAME]='kuali-rds-lifecycle-event-handler'
  [SERVICE]='research-administration'
  [FUNCTION]='kuali'
  [TEMPLATE_BUCKET_PATH]='s3://'$TEMPLATE_BUCKET'/cloudformation/kuali_rds_lifecycle'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../../scripts/common-functions.sh

  if ! isCurrentDir "rds_events" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the rds_events subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    setDefaults

    validateParms
  fi

  runTask
}

validateParms() {
  [ "$task" == 'export' ] && return 0
  [ -z "$HOSTED_ZONE_NAME" ] && echo "Missing HOSTED_ZONE_NAME parameter!" && exit 1
}

stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    if isDryrun ; then
      echo "DRYRUN: aws cloudformation $action --stack-name $(getStackToDelete)"
    else
      aws cloudformation $action --stack-name $(getStackToDelete)
      if ! waitForStackToDelete ; then
        echo "Problem deleting stack!"
        exit 1
      fi
    fi
  else
    # Validate the yaml file(s)
    outputHeading "Validating main template(s)..."
    validateStack silent=true
    [ $? -gt 0 ] && exit 1

    if [ ! -f 'rds_replacement.zip' ] || [ "$EXPORT" == 'true' ] ; then
      exportCode
    fi

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-body "file://./main.yaml" \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'Service' 'SERVICE'
    add_parameter $cmdfile 'Function' 'FUNCTION'
    add_parameter $cmdfile 'BucketName' 'BUCKET_NAME'   
    add_parameter $cmdfile 'HostedZoneName' 'HOSTED_ZONE_NAME'

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'rds'
    addTag $cmdfile 'Subcategory' 'lifecycle'
    echo "      ]'" >> $cmdfile

    runStackActionCommand
  fi
}

# Build and upload the lambda function code:
exportCode() {
  outputHeading "Building, zipping, and uploading lambda code..."
  zipPackageAndCopyToS3 '.' 's3://'$TEMPLATE_BUCKET'/cloudformation/kuali_lambda/rds_replacement.zip'
}

runTask() {
  case "$task" in
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
    export)
      exportCode ;;
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
