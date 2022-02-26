
#!/bin/bash

# You must source common-functions.sh for some functionality used below.

checkTestHarness $@ 2> /dev/null || true

parseArgs $@

isDebug && set -x

validInputs() {
  outputSubHeading "Checking required environment variables and setting default values..."
  local msg=""
  [ -z "$LANDSCAPE" ]  && \
    msg="ERROR: Missing LANDSCAPE value." && echo "$msg"
  [ -z "$TARGET_IMAGE" ]  && \
    msg="ERROR: Missing TARGET_IMAGE value." && echo "$msg"
  [ "$NEW_RELIC_LOGGING" == true ] && NEW_RELIC_AGENT_ENABLED="true" || NEW_RELIC_AGENT_ENABLED="false"
  if isLegacyDeploy ; then
    [ -z "$LEGACY_LANDSCAPE" ] && msg="ERROR: Missing LEGACY_LANDSCAPE" && echo "$msg"
    [ -z "$CROSS_ACCOUNT_ROLE_ARN" ] && msg="ERROR: Missing CROSS_ACCOUNT_ROLE_ARN" && echo "$msg"
  fi
  if usingNewRelic ; then
    NEW_RELIC_LICENSE_KEY="$(aws s3 cp s3://kuali-conf/newrelic/newrelic.license.key - 2> /dev/null)"
    [ -z "$NEW_RELIC_LICENSE_KEY" ] && \
      msg="ERROR: Could not lookup NEW_RELIC_LICENSE_KEY value in s3." && \
      echo "$msg"
    [ -z "$NEW_RELIC_INFRASTRUCTURE_ENABLED" ] && NEW_RELIC_INFRASTRUCTURE_ENABLED='true'
  fi
  [ "$LOGJ2_LOCALHOST_LEVEL" == 'default' ] && LOGJ2_LOCALHOST_LEVEL="info"
  [ "$LOGJ2_CATALINA_LEVEL" == 'default' ] && LOGJ2_CATALINA_LEVEL="info"
  [ -z "$LOGJ2_LOCALHOST_LEVEL" ] && LOGJ2_LOCALHOST_LEVEL="info"
  [ -z "$LOGJ2_CATALINA_LEVEL" ] && LOGJ2_CATALINA_LEVEL="info"

  [ -z "$msg" ] && true || false
}

printVariables() {
  echo "STACK_NAME=$STACK_NAME"
  if isLegacyDeploy ; then
    echo "LEGACY_LANDSCAPE=$LEGACY_LANDSCAPE"
    echo "CROSS_ACCOUNT_ROLE_ARN=$CROSS_ACCOUNT_ROLE_ARN"
  fi
  echo "LANDSCAPE=$LANDSCAPE"
  echo "TARGET_IMAGE=$TARGET_IMAGE"
  echo "NEW_RELIC_LOGGING=$NEW_RELIC_LOGGING"
  echo "NEW_RELIC_LICENSE_KEY=$(obfuscate $NEW_RELIC_LICENSE_KEY)"
  echo "NEW_RELIC_INFRASTRUCTURE_ENABLED=$NEW_RELIC_INFRASTRUCTURE_ENABLED"
  echo "LOGJ2_CATALINA_LEVEL=$LOGJ2_CATALINA_LEVEL"
  echo "LOGJ2_LOCALHOST_LEVEL=$LOGJ2_LOCALHOST_LEVEL"
}

usingNewRelic() {
  [ "$NEW_RELIC_AGENT_ENABLED" == 'true' ] && true || false 
}

runningOnJenkinsServer() {
  [ -d /var/lib/jenkins ] && true || false
}

isLegacyDeploy() {  
  ([ -n "$LEGACY_LANDSCAPE" ] && [ "${STACK_NAME,,}" == 'legacy' ]) && true || false
}

getStackType() {
  isLegacyDeploy && echo 'legacy' && return 0
  aws cloudformation describe-stacks \
    --stack-name $STACK_NAME 2>&1 \
    | jq -r '.Stacks[0].Tags[] | select(.Key == "Subcategory").Value' 2>&1
}

getCommand() {
  local output_dir="$1"
  local printCommand="${2:-"false"}"
  # Example TARGET_IMAGE: 70203350335.dkr.ecr.us-east-1.amazonaws.com/kuali-coeus-feature:2001.0040
  local repo=$(echo "$TARGET_IMAGE" | cut -d':' -f1)
  local tag=$(echo "$TARGET_IMAGE" | cut -d':' -f2)

  obfuscatePassword() {
    [ "$printCommand" == 'true' ] && obfuscate "$1" || echo "$1"
  }

  getCssCommand() {
    echo \
      "      if [ ! -d $output_dir ] ; then
        mkdir -p $output_dir;
      fi
      cd /opt/kuali/scripts
      if [ -n \"\$(docker ps -a --filter name=kuali-research -q)\" ]; then
        docker-compose rm --stop --force kuali-research;
      fi
      EXISTING_IMAGE_ID=\$(docker images \\
            | grep -P \"${repo}\s+${tag}\" \\
            | sed -r -n 's/[[:blank:]]+/ /gp' \\
            | cut -d ' ' -f 3)
      if [ -n \"\${EXISTING_IMAGE_ID}\" ]; then
        docker rmi -f \${EXISTING_IMAGE_ID};
      fi
      
      ec2Host=\$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

      # Create an override file for the kc service (this file \"extends\" the baseline docker-compose config file)
      f='/opt/kuali/scripts/docker-compose-override-kc.yaml'
      echo \"version: '3'\" > \$f
      echo \"services:\" >> \$f
      echo \"  kuali-research:\" >> \$f
      echo \"    image: $TARGET_IMAGE\" >> \$f
      echo \"    environment:\" >> \$f
      echo \"      - EC2_HOSTNAME=\$ec2Host\" >> \$f
      echo \"      - NEW_RELIC_LICENSE_KEY=$(obfuscatePassword "$NEW_RELIC_LICENSE_KEY" "true")\" >> \$f
      echo \"      - NEW_RELIC_AGENT_ENABLED=$NEW_RELIC_AGENT_ENABLED\" >> \$f
      echo \"      - NEW_RELIC_INFRASTRUCTURE_ENABLED=$NEW_RELIC_INFRASTRUCTURE_ENABLED\" >> \$f
      echo \"      - LOGJ2_CATALINA_LEVEL=$LOGJ2_CATALINA_LEVEL\" >> \$f
      echo \"      - LOGJ2_LOCALHOST_LEVEL=$LOGJ2_LOCALHOST_LEVEL\" >> \$f
      echo \"      - JAVA_ENV=$LANDSCAPE\" >> \$f
      
      region=\$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)
      \$(aws ecr get-login --no-include-email --region \$region)

      # Build the up command so as to include all potential override files
      cmd='docker-compose -f docker-compose.yaml -f docker-compose-override-kc.yaml'
      [ -f docker-compose-override-core.yaml ] && cmd=\"\$cmd -f docker-compose-override-core.yaml\"
      [ -f docker-compose-override-portal.yaml ] && cmd=\"\$cmd -f docker-compose-override-portal.yaml\"
      [ -f docker-compose-override-pdf.yaml ] && cmd=\"\$cmd -f docker-compose-override-pdf.yaml\"
      cmd=\"\$cmd up --detach kuali-research 2>&1 | tee $output_dir/last-coeus-run-cmd\"

      # Already running containers should not be affected by the up command as long as their configurations have not changed (ie: via an override file)
      echo \"\$cmd\"
      eval \"\$cmd\"
      sleep 3
      echo ''
      echo \"kuali-research container environment:\"
      docker exec kuali-research env 2> /dev/null"    
  }

  getLegacyCommand() {
    # Unlike the css account, coeus images are not stored in ecr with a "kuali-" prefix, so strip it off.
    local targetImage="$(echo "$TARGET_IMAGE" | cut -d'-' -f2-)"
    echo \
      "      if [ ! -d $output_dir ] ; then
        mkdir -p $output_dir;
      fi
      if [ -n \"\$(docker ps -a --filter name=kuali-research -q)\" ]; then
        docker rm -f kuali-research;
        sleep 2;
        docker network disconnect -f bridge kuali-research 2> /dev/null || true;
      fi
      EXISTING_IMAGE_ID=\$(docker images \\
            | grep -P \"${repo}\s+${tag}\" \\
            | sed -r -n 's/[[:blank:]]+/ /gp' \\
            | cut -d ' ' -f 3)
      if [ -n \"\${EXISTING_IMAGE_ID}\" ]; then
        docker rmi -f \${EXISTING_IMAGE_ID};
      fi
      if [ ! -d /var/log/newrelic ] ; then
        mkdir -p /var/log/newrelic;
      fi
      
      export AWS_DEFAULT_REGION=us-east-1;
      export AWS_DEFAULT_OUTPUT=json;
      aws s3 cp \\
        s3://kuali-research-ec2-setup/${LEGACY_LANDSCAPE}/kuali/main/config/kc-config.xml \\
        /opt/kuali/main/config/kc-config.xml
      evalstr=\$(aws ecr get-login)
      evalstr=\$(echo \$evalstr | sed 's/ -e none//')
      echo \$evalstr > $output_dir/last-ecr-login
      eval \$evalstr
      docker run \\
        -d \\
        -p 8080:8080 \\
        -p 8009:8009 \\
        --log-opt max-size=10m \\
        --log-opt max-file=5 \\
        -e NEW_RELIC_LICENSE_KEY=$(obfuscatePassword "$NEW_RELIC_LICENSE_KEY" "true") \\
        -e NEW_RELIC_AGENT_ENABLED=\"$NEW_RELIC_AGENT_ENABLED\" \\
        -e JAVA_ENV=$NEW_RELIC_ENVIRONMENT \\
        -e EC2_HOSTNAME=\$(echo \$HOSTNAME) \\
        -e LOGJ2_CATALINA_LEVEL=\"$LOGJ2_CATALINA_LEVEL\" \\
        -e LOGJ2_LOCALHOST_LEVEL=\"$LOGJ2_LOCALHOST_LEVEL\" \\
        -h \$(echo \$HOSTNAME) \\
        -v /opt/kuali/main/config:/opt/kuali/main/config \\
        -v /var/log/kuali/printing:/opt/kuali/logs/printing/logs \\
        -v /var/log/kuali/javamelody:/var/log/javamelody \\
        -v /var/log/kuali/attachments:/opt/tomcat/temp/dev/attachments \\
        -v /var/log/tomcat:/opt/tomcat/logs \\
        -v /var/log/newrelic:/var/log/newrelic \\
        --restart unless-stopped \\
        --name kuali-research \\
        $targetImage 2>&1 | tee $output_dir/last-coeus-run-cmd"
  }

  if isLegacyDeploy ; then
    getLegacyCommand
  else
    getCssCommand
  fi
}

# Get the bash command(s) to be sent to the target ec2 instance as a base64 encoded string
getBase64EncodedCommand() {
  getCommand $1 | base64 -w 0
}

# Get a simple bash command to write out a file to be sent to the target ec2 instance as a base64 encoded string.
# This can be run against a real application host because its impact is of no effect to anything (harmless).
getHarmlessBase64EncodedCommand() {
  local output_dir="$1"
  echo "echo 'THIS IS A TEST!' && echo $(date) > $output_dir/last-coeus-run-cmd 2>&1" | base64 -w 0
}

# Use the ssm service to send the command for refreshing the docker container at the specified ec2 host.
# The output of the command will be streamed to an s3 bucket and be available for the jenkins job to display.
sendCommand() {
  local ec2Id="$1"
  local output_dir="$2"

  outputSubHeading "Building ssm command (determine stack type, build, encode)"
  getCommand $output_dir "true"
  local base64="$(getBase64EncodedCommand $output_dir)"
  outputSubHeading "Sending ssm command to refresh docker container at $ec2Id"

  if runningOnJenkinsServer ; then
    if isDryrun ; then
      echo "DRYRUN: sendCommand..."
      return 0
    fi
    finalBase64="$base64"
  else
    # Debugging locally
    if isDryrun ; then
      finalBase64=$(getHarmlessBase64EncodedCommand $output_dir)
    else
      finalBase64="$base64"
    fi
  fi

  if isLegacyDeploy ; then
    STDOUT_BUCKET='kuali-docker-run-stdout'
    if ! assumeCrossAccountRole ; then
      "ERROR: Could not assume role $CROSS_ACCOUNT_ROLE_ARN to invoke legacy account deployment."
      return 1
    fi
  else
    STDOUT_BUCKET='kuali-docker-run-css-nprd-stdout'
    if [ -z "$(aws s3 ls | grep -P "$STDOUT_BUCKET")" ] ; then
      aws s3 mb "s3://$STDOUT_BUCKET"
    fi
  fi

  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$ec2Id" \
    --document-name "AWS-RunShellScript" \
    --comment "Running shell script to pull and run container against a new docker image" \
    --parameters \
          commands="echo >> $output_dir/ssm-kc-received && date >> $output_dir/ssm-kc-received && \
                    echo ${base64} | base64 --decode >> $output_dir/ssm-kc-received && \
                    echo ${base64} | base64 --decode > $output_dir/ssm-kc-last.sh && \
                    sh $output_dir/ssm-kc-last.sh 2>&1" \
    --output text \
    --query "Command.CommandId" \
    --output-s3-bucket-name "$STDOUT_BUCKET" \
    --output-s3-key-prefix "kc")

  echo "COMMAND_ID=$COMMAND_ID"    
}

# Assume a role that exists in the legacy account for the ability to execute an ssm send-command call
assumeCrossAccountRole() {
  echo "Assuming role $CROSS_ACCOUNT_ROLE_ARN"
  ASSUMED_ROLE_PROFILE='CROSS_ACCOUNT_SSM'
  set -x
  local sts=$(aws sts assume-role \
    --role-arn "$CROSS_ACCOUNT_ROLE_ARN" \
    --role-session-name "$ASSUMED_ROLE_PROFILE" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)
  set +x
  if [ -n "$sts" ] ; then
    sts=($sts)
    aws configure set aws_access_key_id ${sts[0]} --profile $ASSUMED_ROLE_PROFILE && \
    aws configure set aws_secret_access_key ${sts[1]} --profile $ASSUMED_ROLE_PROFILE && \
    aws configure set aws_session_token ${sts[2]} --profile $ASSUMED_ROLE_PROFILE && \
    export AWS_PROFILE=$ASSUMED_ROLE_PROFILE
    [ $? -eq 0 ] && local success='true'
  fi

  [ "$success" == 'true' ] && true || false
}

# The file output by ssm send-command won't be available in s3 immediately, so
# making repeated attempts to access it in a loop until it is available.
waitForCommandOutputLogs() {
  local ec2Id="$1"
  local output_dir="$2"
  i=1

  if isLegacyDeploy ; then
    # S3 logs not implemented right now for ssm activity against the legacy account. Maybe later.
    echo "Command issued to ec2 $ec2Id. Check $output_dir on that server for command output."
    return 0
  fi

  if runningOnJenkinsServer ; then
    if isDryrun ; then
      echo "DRYRUN: waitForCommandOutputLogs..."
      return 0
    fi
  fi

  while ((i<200)) ; do
    s3Url="$(s3GetKcSendCommandOutputFileUrl $COMMAND_ID $STDOUT_BUCKET)"
    [ -n "$s3Url" ] && echo "Url to presign is: $s3Url" && break;
    echo "Url to presign not ready. Trying again in 5 seconds..."
    ((i+=1))
    sleep 5
  done

  if [ -n "$s3Url" ] ; then
    # Have the s3 url of the stdout file presigned so a we can access it with a new url that will get around
    # the private access restriction.
    days=7
    seconds="$((60*60*24*${days}))"
    httpUrl="$(aws s3 presign "${s3Url}" --expires-in=${seconds})"
    echo "Access the docker container creation output on the remote EC2 instance ($ec2Id) at:"
    echo " "
    echo "$httpUrl"
    echo " "
    echo "You may have to wait for about a minute for the link to become available"
    echo "(link expires in $days days)"
    echo " "
  else
    echo "WARNING! Could not acquire s3 location of ssm send-command output file!"
    echo "You will have to shell into the ec2 instance and open $output_dir/last-kc-run-cmd to determine how it went."
  fi

}

# Fetch and reset the code from the git repository containing the docker build context
getBashLibFile() {
  echo "Getting bash.lib.sh from git@github.com:bu-ist/kuali-research-docker.git..."
  (
    eval `ssh-agent -k` || true
    eval `ssh-agent -s`
    ssh-add ~/.ssh/bu_github_id_docker_rsa
    if [ -d kuali-research-docker ] ; then
      rm -f -r kuali-research-docker
    fi
    mkdir kuali-research-docker
    cd kuali-research-docker
    git init	
    git config user.email "jenkins@bu.edu"
    git config user.name jenkins
    git config core.sparseCheckout true
    git remote add github git@github.com:bu-ist/kuali-research-docker.git
    echo bash.lib.sh >> .git/info/sparse-checkout
    git fetch github master
    git checkout master 
    eval `ssh-agent -k` || true
  ) && \
  if [ ! -f .gitignore ] || [ -z "$(cat .gitignore | grep -P '^kuali-research-docker')" ] ; then
    echo "" >> .gitignore
    echo 'kuali-research-docker' >> .gitignore
    echo 'kuali-research-docker/*' >> .gitignore
  fi
  source kuali-research-docker/bash.lib.sh
}

issueDockerRefreshCommand() {
  local ec2Id="$1"
  local output_dir='/var/log/jenkins'

  getBashLibFile \
  && \
  sendCommand $ec2Id $output_dir \
  && \
  waitForCommandOutputLogs $ec2Id $output_dir
}

deployToEc2() {
  echo "Stack $STACK_NAME is of type \"ec2\""
  local ec2Id="$(
    aws cloudformation describe-stacks \
      --stack-name $STACK_NAME \
      | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId").OutputValue'
  )"
  issueDockerRefreshCommand "$ec2Id"
}

deployToEc2Alb() {
  echo "Stack $STACK_NAME is of type \"ec2_alb\""
  local stack="$(aws cloudformation describe-stacks --stack-name $STACK_NAME)" 
  local ec2Id1="$(echo "$stack" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId1").OutputValue')"
  local ec2Id2="$(echo "$stack" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId2").OutputValue')"
  issueDockerRefreshCommand "$ec2Id1"
  issueDockerRefreshCommand "$ec2Id2"
}

deployToEcs() {
  echo "Stack $STACK_NAME is of type \"ecs\""
}

deployToLegacyAccount() {
  if [ -z "$LEGACY_LANDSCAPE" ] ; then
    echo "Parameter required: LEGACY_LANDSCAPE"
    echo "Cannot deploy coeus to the legacy account. Fix this or do it by hand."
  else
    case "${LEGACY_LANDSCAPE,,}" in
      sb)
        issueDockerRefreshCommand 'i-099de1c5407493f9b'
        issueDockerRefreshCommand 'i-0c2d2ef87e98f2088'
        ;;
      ci)
        issueDockerRefreshCommand 'i-0258a5f2a87ba7972'
        issueDockerRefreshCommand 'i-0511b83a249cd9fb1'
        ;;
      qa)
        issueDockerRefreshCommand 'i-011ccd29dec6c6d10'
        ;;
      stg)
        issueDockerRefreshCommand 'i-090d188ea237c8bcf'
        issueDockerRefreshCommand 'i-0cb479180574b4ba2'
        ;;
      prod)
        issueDockerRefreshCommand 'i-0534c4e38e6a24009'
        issueDockerRefreshCommand 'i-07d7b5f3e629e89ae'
        ;;
    esac
  fi
}

deploy() {
  outputSubHeading "Determining type of stack for: $STACK_NAME ..."
  local stackType="$(getStackType)"
  case "$stackType" in
    ec2)
      deployToEc2 ;;
    ec2-alb)
      deployToEc2Alb ;;
    ecs)
      deployToEcs ;;
    legacy)
      deployToLegacyAccount ;;
    *)
      echo "ERROR: Cannot determine the type of stack to deploy to!"
      exit 1
      ;;
  esac
}

if validInputs ; then

  printVariables

  deploy
fi

