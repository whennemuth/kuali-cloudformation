#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-dns'
  [GLOBAL_TAG]='kuali-dns'
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_dns'
  [TEMPLATE_PATH]='.'
  [NO_ROLLBACK]='true'
  # [DOMAIN_NAME]='kuali.research.bu.edu'
)

run() {
  source ../scripts/common-functions.sh

  task="${1,,}"
  shift

  if [ "$task" != "test" ] ; then

    parseArgs $@

    setDefaults
  fi

  runTask $@
}

# Route53 is a service that, for logging, supports attaching permission policies to it as a resource, not a principal.
# This means that route53 does not assume a role that grants it permission to log to cloudwatch, but the route53 
# resource itself is associated with the policy that the role would have had.
# SEE: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_compare-resource-policies.html
# Cloudwatch does not support creating a resource-based policy for route53, so it must be created before stack creation.
checkResourceBasedPolicy() {
  echo "Checking for resource based policy for route53 logging..."
  local policyName='kuali-route53-logging-policy'
  local searchResult=$(
    aws logs describe-resource-policies \
      --output text \
      --query 'resourcePolicies[?policyName==`'$policyName'`].{name:policyName}' 2> /dev/null
  )

  [ -n "$searchResult" ] && echo "Policy found." && return 0

  echo "Policy \"$policyName\" not found, creating policy..."

  local accountId="$(aws sts get-caller-identity --output text --query '{Account:Account}')"

  cat <<-EOF > $cmdfile
  aws logs put-resource-policy \\
    --policy-name $policyName \\
    --policy-document '{
    "Version": "2012-10-17", 
    "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "route53.amazonaws.com"
          },
          "Action": [
            "logs:PutLogEvents",
            "logs:CreateLogStream"
          ],
          "Resource": "arn:aws:logs:us-east-1:$accountId:log-group:/aws/route53/*"
        }
      ]
    }'
EOF

  runStackActionCommand
}

# Create, update, or delete the cloudformation stack.
stackAction() {
  local action=$1

  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name ${STACK_NAME}
  else
    # Upload the yaml file(s) to s3
    uploadStack
    [ $? -gt 0 ] && exit 1

    checkResourceBasedPolicy
    echo "Return value: $?"

    cat <<-EOF > $cmdfile
    aws cloudformation $action \\
      --stack-name ${STACK_NAME} \\
      $([ $task == 'update-stack' ] && echo '--no-use-previous-template') \\
      $([ "$NO_ROLLBACK" == 'true' ] && [ $task == 'create-stack' ] && echo '--on-failure DO_NOTHING') \\
      --template-url $BUCKET_URL/dns.yaml \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'GlobalTag' 'GLOBAL_TAG'
    add_parameter $cmdfile 'DomainName' 'DOMAIN_NAME'
    add_parameter $cmdfile 'DBDomainName' 'DB_DOMAIN_NAME'

    echo "      ]'" >> $cmdfile

    runStackActionCommand
  fi
}


runTask() {
  case "$task" in
    validate)
      validateStack silent=true;
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
    delete-stack)
      stackAction "delete-stack" ;;
    check-logging-policy)
      checkResourceBasedPolicy ;;
    test)
      echo 'testing' ;;
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