#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-jenkins'
  [GLOBAL_TAG]='kuali-jenkins'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_jenkins'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [PROFILE]='infnprd'
  # [CAMPUS_SUBNET1]='???'
)

run() {

  source ../scripts/common-functions.sh
  
  if ! isCurrentDir "kuali_jenkins" ; then
    echo "You must run this script from the kuali_jenkins subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  outputHeading "Validating/Parsing parameters..."
  if [ "$task" != "test" ] ; then

    parseArgs $@

    setDefaults
  fi

  runTask
}

# Create, update, or delete the cloudformation stack.
stackAction() {  
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws --profile=$PROFILE cloudformation $action --stack-name ${STACK_NAME}
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
      exit 1
    fi
    outputHeading "Validating and uploading main template(s)..."
    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    cat <<-EOF > $cmdfile
    aws --profile=$PROFILE \\
      cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/jenkins.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'EC2InstanceType' 'EC2_INSTANCE_TYPE'
    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'JenkinsSubnet' 'CAMPUS_SUBNET1'
    add_parameter $cmdfile 'JavaVersion' 'JAVA_VERSION'

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
      if waitForStackToDelete ${STACK_NAME} ; then
        task='create-stack'
        stackAction "create-stack"
      else
        echo "ERROR! Stack deletion failed. Cancelling..."
      fi
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
      test ;;
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