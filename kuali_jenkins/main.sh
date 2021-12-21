#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-jenkins'
  [GLOBAL_TAG]='kuali-jenkins'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_jenkins'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  [S3_REFRESH]='true'
  # [PROFILE]='???'
  # [ADMIN_PASSWORD]='???'
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

getJenkinsInstanceId() {
  filters=(
    'Key=Function,Values='${kualiTags['Function']}
    'Key=Service,Values='${kualiTags['Service']}
    "Key=Name,Values=kuali-jenkins"
  )
  pickEC2InstanceId ${filters[@]} > /dev/null
  cat ec2-instance-id
  rm -f ec2-instance-id
}

# Upload one of, or all the bash scripts the jenkins ec2 instance will need to s3.
uploadScriptsToS3() {
  local singleScript="$1"
  if [ -n "$singleScript" ] ; then
    if [ -f "$singleScript" ] ; then      
      if [ "${singleScript:0:13}" == 'bash-scripts/' ] ; then
        local s3SubPath=${singleScript:13:100} # Assumes var length is under 100 chars
      else
        local s3SubPath=$singleSript
      fi
      cmd="aws s3 cp $singleScript $TEMPLATE_BUCKET_PATH/scripts/$s3SubPath"
      if ! isS3Refresh ; then
        echo "Skipping s3 refresh of $TEMPLATE_BUCKET_PATH/scripts/$s3SubPath"
        return 0
      fi
      (isDryrun || isDebug) && cmd="$cmd --dryrun"
      eval "$cmd"
    else
      if [ -f "bash-scripts/$singleScript" ] ; then
        uploadScriptsToS3 "bash-scripts/$singleScript"
      else
        echo "ERROR! $singleScript cannot be found!"
      fi
    fi
  else
    for script in $(ls -1 bash-scripts/*.sh) ; do
      uploadScriptsToS3 $script
    done
    for script in $(ls -1 bash-scripts/cfn/*.sh) ; do
      uploadScriptsToS3 $script
    done
    for script in $(ls -1 bash-scripts/job/*.sh) ; do
      uploadScriptsToS3 $script
    done
  fi
}

# Download from s3 into the jenkins ec2 instance one of, or all the bash scripts it will need.
remotePullFromS3() {
  local singleScript="$1"
  local cmds=()
  case $singleScript in
    bash-scripts/jenkins-docker.sh | jenkins-docker.sh)
      # This script goes to a different target location on the ec2 instance.
      local cmd="aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/jenkins-docker.sh /etc/init.d/jenkins-docker.sh"
      ;;
    *)
      if [ -n "$singleScript" ] ; then
        if [ "${singleScript:0:13}" == 'bash-scripts/' ] ; then
          singleScript=${singleScript:13:100} # Assumes var length is under 100 chars
        fi
        case ${singleScript:0:4} in
          'cfn/')
            local subdir='_cfn-scripts'
            local shortname=${singleScript:4:100}
            cmds=("aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/$singleScript /var/lib/jenkins/$subdir/$shortname")
            ;;
          'job/')
            local subdir='_job-scripts'
            local shortname=${singleScript:4:100}
            cmds=("aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/$singleScript /var/lib/jenkins/$subdir/$shortname")
            ;;
          *)
            echo "WARNING: No known jenkins ec2 target folder for s3 file download: $singleScript"
            ;;
        esac
      else
        local cmd="aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/jenkins-docker.sh /etc/init.d/jenkins-docker.sh"
        cmds=("${cmds[@]}" "$cmd")
        cmd="aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/cfn/ /var/lib/jenkins/_cfn-scripts/ --recursive" 
        cmds=("${cmds[@]}" "$cmd")
        cmd="aws s3 cp $TEMPLATE_BUCKET_PATH/scripts/job/ /var/lib/jenkins/_job-scripts/ --recursive" 
        cmds=("${cmds[@]}" "$cmd")
      fi
      ;;
  esac

  if [ ${#cmds[@]} -gt 0 ] ; then
    local commands="{\"commands\":[\""
    local counter=1
    for cmd in "${cmds[@]}" ; do
      if [ $counter -eq ${#cmds[@]} ] ; then
        commands="$commands$cmd\"]}"
      else
        commands="$commands$cmd\", \""
      fi
      ((counter++))
    done
    if [ "${DRYRUN,,}" == 'true' ] || [ "${DEBUG,,}" == 'true' ] ; then
      echo $commands
    else
      export AWS_PAGER=""
      aws ssm send-command \
        --instance-ids $(getJenkinsInstanceId) \
        --document-name "AWS-RunShellScript" \
        --comment "Download scripts from s3 to Jenkins ec2 instance" \
        --no-paginate \
        --parameters "$commands"
    fi
  fi
}

# upload to s3 a bash script and remotely trigger the jenkins ec2 to download it.
# If SCRIPT_FILE is empty, then the process applies to ALL scripts.
refreshScripts() {

  uploadScriptsToS3 $SCRIPT_FILE

  remotePullFromS3 $SCRIPT_FILE
}

# Create, update, or delete the cloudformation stack.
stackAction() {  
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name ${STACK_NAME}
  else
    # checkSubnets will also assign a value to VPC_ID
    if ! checkSubnets ; then
      exit 1
    fi
    outputHeading "Validating and uploading main template(s)..."
    # Upload the yaml files to s3
    uploadStack silent
    if [ $? -gt 0 ] ; then      
      echo "Errors encountered while uploading stack! Cancelling..."
      exit 1
    fi

    uploadScriptsToS3

    cat <<-EOF > $cmdfile
    aws \\
      cloudformation $action \\
      $([ $task == 'create-change-set' ] && echo --change-set-name ${STACK_NAME}-$(date +'%s')) \\
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
    add_parameter $cmdfile 'JenkinsVersion' 'JENKINS_VERSION'
    if [ -n "$ADMIN_PASSWORD" ] ; then
      if secretExists 'kuali/jenkins/administrator' ; then
        echo "Secret exists, modify password in secret-string..."
        aws secretsmanager update-secret \
          --secret-id 'kuali/jenkins/administrator' \
          --secret-string '{
            "username": "admin",
            "password": "'$ADMIN_PASSWORD'"
          }'
      else
        echo "Secret does not exist, new secret will be created."
        add_parameter $cmdfile 'JenkinsAdminPassword' 'ADMIN_PASSWORD'
      fi
    fi

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
    upload-scripts)
      uploadScriptsToS3 $SCRIPT_FILE ;;
    refresh-scripts)
      refreshScripts $SCRIPT_FILE ;;
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
    create-change-set)
      task='create-change-set'
      stackAction "create-change-set" ;;
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