#!/bin/bash

declare -A defaults=(
  [STACK_NAME]='kuali-maintenance'
  [SERVICE]='research-administration'
  [FUNCTION]='kuali'
  [NO_ROLLBACK]='true'
  # ----- All other parameters have defaults set in the yaml file itself
)

run() {
  source ../scripts/common-functions.sh

  if ! isCurrentDir "kuali_maintenance" ; then
    echo "Current directory: $(pwd)"
    echo "You must run this script from the kuali_maintenance subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] && [ "$task" != 'validate' ]; then
    outputHeading "Validating/Parsing parameters..."

    parseArgs $@

    setDefaults
  fi

  runTask $@
}

stackAction() {
  local action=$1   

  [ -z "$FULL_STACK_NAME" ] && FULL_STACK_NAME=${STACK_NAME}-${LANDSCAPE}
  if [ "$action" == 'delete-stack' ] ; then
    aws cloudformation $action --stack-name $FULL_STACK_NAME
    if ! waitForStackToDelete ; then
      echo "Problem deleting stack!"
      exit 1
    fi
  else
    # checkSubnetsInLegacyAccount will also assign a value to VPC_ID
    outputHeading "Looking up VPC/Subnet information..."
    if ! checkSubnetsInLegacyAccount ; then
      exit 1
    fi

    outputHeading "Looking up ID of security group belonging to the elb..."
    setELBSecurityGroupID && echo "ELB_SECURITY_GROUP_ID=$ELB_SECURITY_GROUP_ID"

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
      --template-body "file://./ec2.yaml" \\
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
      --parameters '[
EOF

    add_parameter $cmdfile 'Landscape' 'LANDSCAPE'
    add_parameter $cmdfile 'Service' 'SERVICE'
    add_parameter $cmdfile 'Function' 'FUNCTION'
    add_parameter $cmdfile 'VpcId' 'VpcId'
    add_parameter $cmdfile 'CampusSubnet' 'CAMPUS_SUBNET1'
    add_parameter $cmdfile 'EC2InstanceType' 'EC2_INSTANCE_TYPE'
    add_parameter $cmdfile 'ELBSecurityGroupId' 'ELB_SECURITY_GROUP_ID'

    echo "      ]' \\" >> $cmdfile
    echo "      --tags '[" >> $cmdfile
    addStandardTags
    addTag $cmdfile 'Category' 'maintenance'
    addTag $cmdfile 'Subcategory' 'ec2'
    echo "      ]'" >> $cmdfile

    runStackActionCommand

  fi
}

# Get the arn for the elb corresponding to LANDSCAPE and set it globally
setELBArn() {
  if [ -z "$ELB_ARN" ] ; then
    ELB_ARN="$(
      aws resourcegroupstaggingapi get-resources \
        --resource-type-filters elasticloadbalancing:loadbalancer \
        --tag-filters 'Key=Landscape,Values='$LANDSCAPE \
        --output text \
        --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null
    )"
  fi
  [ -n "$ELB_ARN" ] && true || false
}

# Strip out the name of the globally set elb arn and set it globally
setELBName() {
  if [ -z "$ELB_NAME" ] ; then
    if setELBArn ; then
      ELB_NAME="$(echo $ELB_ARN | cut -d'/' -f2 2> /dev/null)"
    fi
  fi
  [ -n "$ELB_NAME" ] && true || false
}

# From the globally set elb name, determine the associated security group id and set it globally.
setELBSecurityGroupID() {
  if setELBName ; then
    local sgId=$(
      aws elb describe-load-balancers \
        --load-balancer-name $ELB_NAME \
        --output text \
        --query 'LoadBalancerDescriptions[].SecurityGroups[]' 2> /dev/null)
    if [ -n "$sgId" ] ; then
      ELB_SECURITY_GROUP_ID="$sgId"
    else
      echo "ERROR! Could not determine security group ID"
      exit 1
    fi
  else
    echo "ERROR! Could not determine load balancer name"
    exit 1
  fi
}

# Print out the ids of the ec2 instances registered with the elb.
getELBRegisteredInstanceIds() {
  if setELBName ; then
    aws elb describe-load-balancers \
      --load-balancer-name $ELB_NAME \
      --output text \
      --query 'LoadBalancerDescriptions[].Instances[]' 2> /dev/null
  fi
}

# Based on tagging, get the maintenance ec2 instance for the provided landscape and print out its id.
getMaintInstanceId() {
  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters ec2:instance \
    --tag-filters \
        'Key=Service,Values='${kualiTags["Service"]} \
        'Key=Function,Values='${kualiTags["Function"]} \
        'Key=Landscape,Values='$LANDSCAPE \
        'Key=Category,Values=maintenance' \
    --output text \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null \
    | sed 's|/|\n|g' \
    | grep -iP '^i\-[a-zA-Z\d]+$'
}

# Based on tagging, get the application ec2 instance(s) for the provided landscape and print out the id(s).
getAppInstanceIds() {
  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters ec2:instance \
    --tag-filters \
        'Key=Service,Values='${kualiTags["Service"]} \
        'Key=Function,Values='${kualiTags["Function"]} \
        'Key=Landscape,Values='$LANDSCAPE \
        'Key=Category,Values=application' \
    --output text \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null \
    | sed 's|/|\n|g' \
    | grep -iP '^i\-[a-zA-Z\d]+$'
}

# Register or deregister ec2 instance(s) from the elb.
changeELBInstances() {
  if setELBName ; then
    local ec2Ids=''
    while read i ; do
      if [ -n "$ec2Ids" ] ; then
        ec2Ids="$ec2Ids $(echo $i)"
      else
        ec2Ids="$(echo $i)"
      fi
    done

    case "${1,,}" in
      remove)
        local task='deregister-instances-from-load-balancer' ;;
      add)
        local task='register-instances-with-load-balancer' ;;
      *)
        echo "ERROR! add/remove parameter not specified." && exit 1 ;;
    esac

    if [ -n "$ec2Ids" ] ; then
      local cmd="aws elb $task --load-balancer-name $ELB_NAME --instances $ec2Ids"
      echo "$cmd"
      isDryrun && return 0
      eval "$cmd"
    else
      echo "ERROR! Cannot find any ec2 instances to deregister from: $ELB_NAME"
      exit 1
    fi
  else
    echo "ERROR! Cannot find ELB for landscape: $LANDSCAPE"
    exit 1
  fi
}

# Swap out the current ec2 instances from the elb with alternate instance(s).
# If application servers are currently registered with the elb, swap them out for "kuali has moved" instance.
# If "kuali has moved" instance is currently registered, swap them out for the application server instances.
swapElbInstances() {

  outputHeading "Swapping elb ec2 instances"
  
  [ -z "$LANDSCAPE" ] && echo "ERROR! Missing LANDSCAPE parameter." && exit 1

  # Get what type (maintenance or application) of instance(s) last deregistered from the elb, and print out the other type.
  getTypeToAdd() {
    local removed=$(echo "$DEREGISTERED_EC2S" | sed 's/ /\n/g' | wc -l)
    if [ $removed -gt 1 ] ; then
      # More than on ec2 instance was just deregistered from the elb - must be kuali application instances.
      echo 'maint'
    else
      local ec2Id="$DEREGISTERED_EC2S"
      if isMaintenanceEC2 "$ec2Id" ; then
        echo 'app'
      else
        # The last ec2 deregistration from the elb must have involved a single kuali appliation instance.
        echo 'maint'
      fi
    fi
  }

  deregisterExistingEC2sFromELB() {
    echo "Deregistering existing ec2 instance(s) from ELB..."
    DEREGISTERED_EC2S=$(getELBRegisteredInstanceIds)
    echo "$DEREGISTERED_EC2S" | changeELBInstances 'remove'
  }

  registerNewEC2sWithELB() {
    case "$(getTypeToAdd)" in
      maint) 
        echo 'Registering maintenance ec2 instance with ELB...'        
        getMaintInstanceId | changeELBInstances 'add' ;;
      app) 
        echo 'Registering application ec2 instance(s) with ELB...'
        getAppInstanceIds | changeELBInstances 'add' ;;
    esac
  }

  deregisterExistingEC2sFromELB 
  
  registerNewEC2sWithELB
}

isMaintenanceEC2() {
  local ec2Id=$1
  local maint=$(aws ec2 describe-instances \
    --instance-ids $ec2Id \
    --output text \
    --query 'Reservations[].Instances[].Tags[?Key==`Category`&&Value==`maintenance`]' 2> /dev/null
  )
  if [ -z "$maint" ] ; then
    if isMicroEC2 "$ec2Id" ; then
      # No kuali application server could be as small as a micro, so this must be a maintenance instance.
      maint="true"
    fi
  fi
  [ -n "$maint" ] && true || false
}

isMicroEC2() {
  local ec2Id=$1
  local micro=$(aws ec2 describe-instances \
    --instance-ids $ec2Id \
    --output text \
    --query 'Reservations[].Instances[].{typ:InstanceType}' 2> /dev/null | grep 'micro'
  )
  [ -n "$micro" ] && true || false
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
    elb-swapout)
      parseArgs $@
      setDefaults
      swapElbInstances ;;
    test)
      echo "NOT IMPLEMENTED" ;;
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
