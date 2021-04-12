#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-mongo'
  [GLOBAL_TAG]='kuali-mongo'
  [LANDSCAPE]='sb'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_mongo'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # [PROFILE]='???'
  # [PRIVATE_SUBNET1]='???'
  # [APP_SECURITY_GROUP_ID]='???'
)

run() {

  source ../scripts/common-functions.sh
  
  if ! isCurrentDir "kuali_mongo" ; then
    echo "You must run this script from the kuali_mongo subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] ; then

    parseArgs $@

    setDefaults
  fi

  runTask
}

# Create, update, or delete the cloudformation stack.
stackAction() {  
  local action=$1

  [ -z "$FULL_STACK_NAME" ] && FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $FULL_STACK_NAME
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
      exit 1
    fi
    # Upload the yaml files to s3
    uploadStack silent
    [ $? -gt 0 ] && exit 1

    # validateStack silent ../kuali_campus_security/main.yaml > /dev/null
    validateStack silent ../kuali_campus_security/main.yaml
    [ $? -gt 0 ] && exit 1
    aws s3 cp ../kuali_campus_security/main.yaml s3://$TEMPLATE_BUCKET_NAME/cloudformation/kuali_campus_security/

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      --stack-name ${FULL_STACK_NAME} \\
      $([ $task != 'create-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/mongo.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'Baseline' 'BASELINE'
    add_parameter $cmdfile 'EC2InstanceType' 'EC2_INSTANCE_TYPE'
    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'MongoSubnet' 'PRIVATE_SUBNET1'
    add_parameter $cmdfile 'CampusSubnetCIDR1' 'CAMPUS_SUBNET1_CIDR'
    add_parameter $cmdfile 'CampusSubnetCIDR2' 'CAMPUS_SUBNET2_CIDR'
    add_parameter $cmdfile 'ApplicationSecurityGroupId' 'APP_SECURITY_GROUP_ID'

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
      if waitForStackToDelete ${STACK_NAME}-${LANDSCAPE} ; then
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