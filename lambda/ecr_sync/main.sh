declare TEMPLATE_BUCKET=${TEMPLATE_BUCKET:-"kuali-conf"}
declare -A defaults=(
  [STACK_NAME]='kuali-trusted-lambda-role'
  [SERVICE]='research-administration'
  [FUNCTION]='kuali'
  [TEMPLATE_BUCKET_PATH]='s3://'$TEMPLATE_BUCKET'/cloudformation/kuali_ecr_sync'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../../scripts/common-functions.sh

  if ! isCurrentDir "ecr_sync" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the ecr_sync subdirectory!."
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
  case "${SYNC_PARTICIPANT,,}" in
    source)
      YAML_FILE='sync-source.yaml'
      ;;
    target)
      YAML_FILE='sync-target.yaml'
      ;;
    *)
      if [ -z "$SYNC_PARTICIPANT" ] ; then
        echo "SYNC_PARTICIPANT parameter missing!"
      elif [ "${SYNC_PARTICIPANT}" != 'source' ] && [ "${SYNC_PARTICIPANT}" != 'target' ] ; then
        echo "SYNC_PARTICIPANT parameter valid values: [\"source\", \"target\"]"
      fi
      exit 1
      ;;
  esac
}

stackAction() {
  local action=$1   

  if [ -z "$FULL_STACK_NAME" ] ; then
    if [ -n "$LANDSCAPE" ] ; then
      FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
    else
      FULL_STACK_NAME=${STACK_NAME}
    fi
  fi
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
    if [ "${SYNC_PARTICIPANT,,}" == 'source' ] ; then
      # checkSubnets will also assign a value to VPC_ID
      outputHeading "Looking up VPC/Subnet information..."
      if ! checkSubnets ; then
        exit 1
      fi
    fi

    # Validate the yaml file(s)
    outputHeading "Validating main template(s)..."
    validateStack silent=true
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${FULL_STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-body "file://./$YAML_FILE" \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'Service' 'SERVICE'
    add_parameter $cmdfile 'Function' 'FUNCTION'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'CampusSubnet' 'CAMPUS_SUBNET1'
    add_parameter $cmdfile 'TrustingAccount' 'TRUSTING_ACCOUNT'
    add_parameter $cmdfile 'TrustedAccount' 'TRUSTED_ACCOUNT'
    add_parameter $cmdfile 'TrustingRoleName' 'TRUSTING_ROLE_NAME'
    add_parameter $cmdfile 'TrustedRoleName' 'TRUSTED_ROLE_NAME'

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'ecr'
    addTag $cmdfile 'Subcategory' 'replication'
    echo "      ]'" >> $cmdfile

    runStackActionCommand
  fi
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
