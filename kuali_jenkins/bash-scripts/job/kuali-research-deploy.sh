
#!/bin/bash

# You must source common-functions.sh for some functionality used below.

isDebug && set -x

outputHeadingCounter=1

validInputs() {
  outputHeading "Checking required environment variables and setting default values..."
  local msg=""
  [ -z "$LANDSCAPE" ]  && \
    msg="ERROR: Missing LANDSCAPE value." && echo "$msg"
  [ -z "$ECR_REGISTRY_URL" ] && \
    msg="ERROR: Missing ECR_REGISTRY_URL value." && echo "$msg"
  [ -z "$REGISTRY_REPO_NAME" ] && \
    msg="ERROR: Missing REGISTRY_REPO_NAME value." && echo "$msg"
  [ -z "$POM_VERSION" ] && \
    msg="ERROR: Missing POM_VERSION value." && echo "$msg"
  [ "$NEW_RELIC_LOGGING" == true ] && NEW_RELIC_AGENT_ENABLED="true" || NEW_RELIC_AGENT_ENABLED="false"
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
  echo "LANDSCAPE=$LANDSCAPE"
  echo "BASELINE=$BASELINE"
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"
  echo "REGISTRY_REPO_NAME=$REGISTRY_REPO_NAME"
  echo "POM_VERSION=$POM_VERSION"
  echo "NEW_RELIC_LOGGING=$NEW_RELIC_LOGGING"
  echo "NEW_RELIC_LICENSE_KEY=$(obfuscate $NEW_RELIC_LICENSE_KEY)"
  echo "NEW_RELIC_INFRASTRUCTURE_ENABLED=$NEW_RELIC_INFRASTRUCTURE_ENABLED"
  echo "LOGJ2_CATALINA_LEVEL=$LOGJ2_CATALINA_LEVEL"
  echo "LOGJ2_LOCALHOST_LEVEL=$LOGJ2_LOCALHOST_LEVEL"
}

usingNewRelic() {
  [ "$NEW_RELIC_AGENT_ENABLED" == 'true' ] && true || false 
}

getStackType() {
  local stackname="$1"
  aws cloudformation describe-stacks \
    --stack-name $stackname \
    | jq -r '.Stacks[0].Tags[] | select(.Key == "Subcategory").Value' 2> /dev/null
}

# Get the bash command(s) to be sent to the target ec2 instance as a base64 encoded string
getBase64EncodedCommand() {
  local output_dir="$1"
  
  if [ "${POM_VERSION:0:1}" == '@' ] ; then
    NEW_IMAGE="${ECR_REGISTRY_URL}/${REGISTRY_REPO_NAME}${POM_VERSION}"
  else
    NEW_IMAGE="${ECR_REGISTRY_URL}/${REGISTRY_REPO_NAME}:${POM_VERSION}"
  fi

  echo \
    "if [ ! -d $output_dir ] ; then
      mkdir -p $output_dir;
    fi
    cd /opt/kuali/scripts
    if [ -n \"\$(docker ps -a --filter name=kuali-research -q)\" ]; then
      docker-compose rm --stop --force kuali-research;
    fi
    EXISTING_IMAGE_ID=\$(docker images \\
          | grep -P \"${ECR_REGISTRY_URL}/${REGISTRY_REPO_NAME}\s+${POM_VERSION}\" \\
          | sed -r -n 's/[[:blank:]]+/ /gp' \\
          | cut -d ' ' -f 3)
    if [ -n \"\${EXISTING_IMAGE_ID}\" ]; then
      docker rmi -f \${EXISTING_IMAGE_ID};
    fi
    
    # Create an override file for the kc service (this file \"extends\" the baseline docker-compose config file)
    f='/opt/kuali/scripts/docker-compose-override-kc.yaml'
    echo \"version: '3'\" > \$f
    echo \"services:\" >> \$f
    echo \"  kuali-research:\" >> \$f
    echo \"    image: $NEW_IMAGE\" >> \$f
    echo \"    environment:\" >> \$f
    echo \"      - NEW_RELIC_LICENSE_KEY=$NEW_RELIC_LICENSE_KEY\" >> \$f
    echo \"      - NEW_RELIC_LICENSE_KEY=$NEW_RELIC_LICENSE_KEY\" >> \$f
    echo \"      - NEW_RELIC_AGENT_ENABLED=$NEW_RELIC_AGENT_ENABLED\" >> \$f
    echo \"      - NEW_RELIC_INFRASTRUCTURE_ENABLED=$NEW_RELIC_INFRASTRUCTURE_ENABLED\" >> \$f
    echo \"      - JAVA_ENV=$LANDSCAPE\" >> \$f
    
    \$(aws ecr get-login --no-include-email)

    # Build the up command so as to include all potential override files
    cmd='docker-compose -f docker-compose.yaml -f docker-compose-override-kc.yaml'
    [ -f docker-compose-override-core.yaml ] && cmd=\"\$cmd -f docker-compose-override-core.yaml\"
    [ -f docker-compose-override-portal.yaml ] && cmd=\"\$cmd -f docker-compose-override-portal.yaml\"
    [ -f docker-compose-override-pdf.yaml ] && cmd=\"\$cmd -f docker-compose-override-pdf.yaml\"
    cmd=\"\$cmd up --detach > $output_dir/last-coeus-run-cmd 2>&1\"

    # Already running containers should not be affected by the up command as long as their configurations have not changed (ie: via an override file)
    eval \"\$cmd\"" | base64 -w 0
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
  local base64="$(getBase64EncodedCommand $output_dir)"
  outputHeading "Sending ssm command to refresh docker container at $ec2Id"

  if isDryrun || isDebug ; then
    finalBase64=$(getHarmlessBase64EncodedCommand $output_dir)
  else
    finalBase64="$base64"
  fi

  STDOUT_BUCKET='kuali-docker-run-css-nprd-stdout'
  if [ -z "$(aws s3 ls | grep -P "$STDOUT_BUCKET")" ] ; then
    aws s3 mb "s3://$STDOUT_BUCKET"
  fi

  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$ec2Id" \
    --document-name "AWS-RunShellScript" \
    --comment "Running shell script to pull and run container against a new docker image for ${REGISTRY_REPO_NAME}" \
    --parameters \
          commands="echo >> $output_dir/ssm-kc-received && date >> $output_dir/ssm-kc-received && \
                    echo ${base64} | base64 --decode >> $output_dir/ssm-kc-received && \
                    echo ${base64} | base64 --decode > $output_dir/ssm-kc-last.sh && \
                    echo ${finalBase64} | base64 --decode | sh 2>&1" \
    --output text \
    --query "Command.CommandId" \
    --output-s3-bucket-name "$STDOUT_BUCKET" \
    --output-s3-key-prefix "kc")

  echo "COMMAND_ID=$COMMAND_ID"    
}

# The file output by ssm send-command won't be available in s3 immediately, so
# making repeated attempts to access it in a loop until it is available.
waitForCommandOutputLogs() {
  local ec2Id="$1"
  local output_dir="$2"
  i=1
  while ((i<100)) ; do
    s3Url="$(s3GetKcSendCommandOutputFileUrl $COMMAND_ID $STDOUT_BUCKET)"
    [ -n "$s3Url" ] && echo "Url to presign is: $s3Url" && break;
    echo "Url to presign not ready. Trying again in 3 seconds..."
    ((i+=1))
    sleep 3
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
      --stack-name $stackname \
      | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId").OutputValue'
  )"
  issueDockerRefreshCommand "$ec2Id"
}

deployToEc2Alb() {
  echo "Stack $STACK_NAME is of type \"ec2_alb\""
  local stackname="$1"
  local stack="$(aws cloudformation describe-stacks --stack-name $stackname)" 
  local ec2Id1="$(echo "$stack" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId1").OutputValue')"
  local ec2Id2="$(echo "$stack" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "InstanceId2").OutputValue')"
  issueDockerRefreshCommand "$ec2Id1"
  issueDockerRefreshCommand "$ec2Id2"
}

deployToEcs() {
  echo "Stack $STACK_NAME is of type \"ecs\""
}

deploy() {
  outputHeading "Determining type of stack for: $STACK_NAME ..."
  case "$(getStackType $STACK_NAME)" in
    ec2)
      deployToEc2 ;;
    ec2-alb)
      deployToEc2Alb ;;
    ecs)
      deployToEcs ;;
    *)
      echo "ERROR: Cannot determine the type of stack to deploy to!"
      exit 1
      ;;
  esac
}

checkTestHarness $@ 2> /dev/null

if validInputs ; then

  printVariables

  deploy
fi

