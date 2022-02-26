declare -A defaults=(
  [STACK_NAME]='kuali-trusted-css-jenkins-role'
  [SERVICE]='research-administration'
  [FUNCTION]='kuali'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_jenkins'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_jenkins" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the kuali_jenkins subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then

    parseArgs $@

    setDefaults
  fi

  runTask
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
    validateStack silent=true
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-body "file://./cross-account-access.yaml" \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'Service' 'SERVICE'
    add_parameter $cmdfile 'Function' 'FUNCTION'
    add_parameter $cmdfile 'TrustedAccount' 'TRUSTED_ACCOUNT'
    add_parameter $cmdfile 'TrustingRoleName' 'TRUSTING_ROLE_NAME'
    add_parameter $cmdfile 'TrustedRoleName' 'TRUSTED_ROLE_NAME'

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'ssm'
    addTag $cmdfile 'Subcategory' 'iam'
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

# EXAMPLE: sh cross-account-access.sh create-stack profile=legacy dryrun=true