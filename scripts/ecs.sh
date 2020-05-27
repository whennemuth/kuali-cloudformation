#!/bin/bash

declare -A defaults=(
  [bucketPath]='s3://kuali-research-ec2-setup/ecs/cloudformation'
  [templatePath]='/c/whennemuth/workspaces/ecs_workspace/cloud-formation/kuali'
  [templateType]='yaml'
  [ConfigBucket]='kuali-research-ec2-setup'
  [KcImage]='730096353738.dkr.ecr.us-east-1.amazonaws.com/coeus-sandbox:2001.0040'
  [CoreImage]='730096353738.dkr.ecr.us-east-1.amazonaws.com/core:2001.0040'
  [PortalImage]='730096353738.dkr.ecr.us-east-1.amazonaws.com/portal:2001.0040'
  [PdfImage]='730096353738.dkr.ecr.us-east-1.amazonaws.com/research-pdf:2002.0003'
  [EC2InstanceType]='m4.large'
  [Landscape]='sb'
)

declare -a extensions=(
  json
  template
  yaml
  yml
)

cmdfile=last-ecs-cmd.sh

ecsValidate() {
  local here="$(pwd)"
  cd $templateDir

  for extension in "${extensions[@]}" ; do
    # echo "$({ find . -type f -iname '*.yaml' & find . -type f -iname '*.template'; })" | \
    find . -type f -iname "*.$extension" | \
    while read line; do \
      local f=$(printf "$line" | sed 's/^.\///'); \
      [ -n "$templateName" ] && [ "$templateName" != "$f" ] && continue; \
      printf $f; \
      aws cloudformation validate-template --template-body "file://./$f"
      echo " "
    done
  done
  cd $here
}


ecsUpload() {
  if [ -f $templatePath ] ; then
    bucketPath=$bucketPath/$templateName
    echo "aws s3 cp  $templatePath $bucketPath" > $cmdfile
  else

    cat <<-EOF > $cmdfile
		aws s3 cp  $templatePath $bucketPath \\
		  --exclude=* \\
		  $(for ext in ${extensions[@]} ; do echo -n '--include=*.'${ext}' ' ; done) \\
		  --recursive
		EOF
  fi

  if [ "$debug" ] ; then
    cat $cmdfile
    return 0
  fi

  printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  read answer
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."
}


ecsStackAction() {  
  if [ $# -ge 1 ] ; then
    local action=$1

    if [ "$action" == 'delete-stack' ] ; then
      aws cloudformation $action --stack-name $stackName
      
      [ $? -gt 0 ] && echo "Cancelling..." && return 1
    else
      ecsUpload

      # local parm1="ParameterKey=ConfigBucket,ParameterValue=$ConfigBucket"
      # local parm2="ParameterKey=KcImage,ParameterValue=$KcImage"
      # local parm3="ParameterKey=CoreImage,ParameterValue=$CoreImage"
      # local parm4="ParameterKey=PortalImage,ParameterValue=$PortalImage"
      # local parm5="ParameterKey=PdfImage,ParameterValue=$PdfImage"
      # local parm6="ParameterKey=EC2InstanceType,ParameterValue=$EC2InstanceType"
      # local parm7="ParameterKey=Landscape,ParameterValue=$Landscape"
      # local parms="$parm1 $parm2 $parm3 $parm4 $parm5 $parm6 $parm7"

			cat <<-EOF > $cmdfile
			aws \\
			  cloudformation $action \\
			  --stack-name $stackName \\
			  $([ $task != 'create' ] && echo '--no-use-previous-template') \\
			  --template-url $bucketUrl/$templateName \\
			  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\
			  --parameters '[
			    { 
			      "ParameterKey" : "ConfigBucket",
			      "ParameterValue" : "$ConfigBucket"
			    },
			    { 
			      "ParameterKey" : "KcImage",
			      "ParameterValue" : "$KcImage"
			    },
			    { 
			      "ParameterKey" : "CoreImage",
			      "ParameterValue" : "$CoreImage"
			    },
			    { 
			      "ParameterKey" : "PortalImage",
			      "ParameterValue" : "$PortalImage"
			    },
			    { 
			      "ParameterKey" : "PdfImage",
			      "ParameterValue" : "$PdfImage"
			    },
			    { 
			      "ParameterKey" : "EC2InstanceType",
			      "ParameterValue" : "$EC2InstanceType"
			    },
			    { 
			      "ParameterKey" : "Landscape",
			      "ParameterValue" : "$Landscape"
			    }
			  ]'
			EOF

      if [ "$debug" ] ; then
        cat $cmdfile
        exit 0
      fi

      printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
      read answer
      [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."

      [ $? -gt 0 ] && echo "Cancelling..." && return 1

      # watchStack $stackName
    fi

    return 0
  fi
  echo "INVALID/MISSING stack action parameter required."
}

ecsMetaRefresh() {
  getInstanceId() (
    aws cloudformation describe-stack-resources \
      --stack-name $stackName \
      --logical-resource-id $logicalResourceId \
      | jq '.StackResources[0].PhysicalResourceId' \
      | sed 's/"//g'
  )

  local instanceId="$(getInstanceId)"
  
  if [ -z "$instanceId" ] ; then
    echo "ERROR! Cannot determine instanceId in stack \"$stackName\""
    exit 1
  else
    echo "instanceId = $instanceId"
  fi

  printf "Enter the name of the configset to run: "
  read configset
  # NOTE: The following does not seem to work properly:
  #       --parameters commands="/opt/aws/bin/cfn-init -v --configsets $configset --region "us-east-1" --stack "ECS-EC2-test" --resource $logicalResourceId"
  # Could be a windows thing, or could be a complexity of using bash to execute python over through SSM.
	cat <<-EOF > $cmdfile
	aws ssm send-command \\
		--instance-ids "${instanceId}" \\
		--document-name "AWS-RunShellScript" \\
		--comment "Implementing cloud formation metadata changes on ec2 instance $logicalResourceId ($instanceId)" \\
		--parameters \\
		'{"commands":["/opt/aws/bin/cfn-init -v --configsets '"$configset"' --region \"us-east-1\" --stack \"$stackName\" --resource $logicalResourceId"]}'
	EOF

  if [ "$debug" ] ; then
    cat $cmdfile
    exit 0
  fi

  printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  read answer
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."
}


parseValue() {
  local cmd=""

  # Blank out prior values:
  [ "$#" == '3' ] && eval "$3="
  [ "$#" == '2' ] && eval "$2="

  if [ -n "$2" ] && [ "${2:0:1}" == '-' ] ; then
    # Named arg found with no value (it is followed by another named arg)
    echo "echo 'ERROR! $1 has no value!' && exit 1"
    exit 1
  elif [ -n "$2" ] && [ "$#" == "3" ] ; then
    # Named arg found with a value
    cmd="$3=\"$2\" && shift 2"
  elif [ -n "$2" ] ; then
    # Named arg found with no value
    echo "echo 'ERROR! $1 has no value!' && exit 1"
    exit 1
  fi

  echo "$cmd"
}

parseargs() {
  local posargs=""

  while (( "$#" )); do
    case "$1" in
      --task)
        eval "$(parseValue $1 "$2" 'task')" 
        task="${task,,}";;
      -t|--template-path)
        eval "$(parseValue $1 "$2" 'templatePath')" ;;
      --template-type)
        eval "$(parseValue $1 "$2" 'templateType')" ;;
      -b|--bucket-path)
        eval "$(parseValue $1 "$2" 'bucketPath')" ;;
      -s|--stack-name)
        eval "$(parseValue $1 "$2" 'stackName')" ;;
      -c|--config-bucket)
        eval "$(parseValue $1 "$2" 'ConfigBucket')" ;;
      --kc-image)
        eval "$(parseValue $1 "$2" 'KcImage')" ;;
      --core-image)
        eval "$(parseValue $1 "$2" 'CoreImage')" ;;
      --portal-image)
        eval "$(parseValue $1 "$2" 'PortalImage')" ;;
      --pdf-image)
        eval "$(parseValue $1 "$2" 'PdfImage')" ;;
      -e|--ec2-instance-type)
        eval "$(parseValue $1 "$2" 'EC2InstanceType')" ;;
      -l|--landscape)
        eval "$(parseValue $1 "$2" 'Landscape')" ;;
      -p|--print-variables)
        eval "$(parseValue $1 "$2" 'printVariables')" ;;
      -r|--logical-resource-id)
        eval "$(parseValue $1 "$2" 'logicalResourceId')" ;;
      -p|--print-variables)
        printVariables="true"
        shift
        ;;
      -d|--debug)
        debug="true"
        printVariables="true"
        shift
        ;;
      -*|--*=) # unsupported flags
        echo "Error: Unsupported flag $1" >&2
        printusage
        exit 1
        ;;
      *) # preserve positional arguments (should not be any more than the leading command, but collect then anyway) 
        posargs="$posargs $1"
        shift
        ;;
    esac
  done

  # set positional arguments in their proper place
  eval set -- "$posargs"

  # Trim off any trailing forward slashes
  templatePath=$(echo "$templatePath" | sed 's/\/*$//')

  # Nested function to set bucket path
  getBucketPath() (
    [ -z "$bucketPath" ] && bucketPath=${defaults[bucketPath]}
    bucketPath=$(echo "$bucketPath" | sed 's/\/*$//')
    if [ "${templatePath:0:1}" == '/' ] ; then
      # Get the current directory
      local here=$(pwd)
      if [ "$here" == "$templatePath" ] ; then
        echo $bucketPath
        exit 0
      fi
      # Get the length of the current directory
      local herelen=$(echo $here | wc -c)
      # Get the leftmost part of templatePath up to the length of the current directory path.
      local start=${templatePath:0:(( $herelen-1 ))}
      
      if [ "$start" == "$here" ] ; then
        templatePath=${templatePath:$herelen}
        [ "${templatePath:0:1}" == '/' ] && templatePath=${templatePath:1}
        getBucketPath
      else
        echo "ERROR: Cannot determine bucket path!"
        exit 1
      fi
    elif [ "${templatePath:0:2}" == './' ] ; then
      templatePath=${templatePath:2}
      getBucketPath
    elif [ "${templatePath:0:1}" == '.' ] ; then
      templatePath=$(pwd)
      getBucketPath
    else
      if [ -f "$templatePath" ] ; then
        bucketPath=$bucketPath/$(dirname $templatePath)
      else
        bucketPath=$bucketPath/$templatePath
      fi
      echo $bucketPath
    fi
  )

  case $task in
    validate|upload|examples)
      [ -z "$templatePath" ] && templatePath=${defaults[templatePath]}
      if [ -f $templatePath ] ; then
        templateDir=$(dirname $templatePath)
        templateName=$(echo $templatePath | grep -oP '[^/]+$')
      elif [ -d $templatePath ] ; then
        templateDir=$templatePath
      elif [ -f $(pwd)/$templatePath ] ; then
        templatePath=$(pwd)/$templatePath
        templateDir=$(dirname $templatePath)
        templateName=$(echo $templatePath | grep -oP '[^/]+$')
      elif [ -d $(pwd)/$templatePath ] ; then
        templateDir=$(pwd)/$templatePath
      else 
        cat <<-EOF
				INVALID PARAMETER: template-path
				  "$templatePath" does not exist
				  and...  
				  "$(pwd)/$templatePath" does not exist"
				EOF
        exit 1
      fi

      # Set and array to cover the different variations of file extension a particular template format could have
      if [ "$templateType" == 'json' ] ; then
        extensions=(json template)
      elif [ "$templateType" == 'yaml' ] ; then
        extensions=(yaml yml)
      fi

      case $task in
        validate)
          templateType=${templateType,,}
          [ -z "$templateType" ] && templateType=${defaults[templateType]}
          if [ "$templateType" != "json" ] && [ "$templateType" != "yaml" ] ; then
            echo "INVALID PARAMETER: template-type allowed values: json or yaml"  
            exit 1
          fi
          ;;
        upload)
          bucketPath="$(getBucketPath)"
          ;;
      esac
      ;;
    create|update|delete)
      [ -z "$stackName" ] && echo "MISSING PARAMETER: stack-name" && exit 1
      case $task in
        create|update)
          [ -z "$templatePath" ] && echo "MISSING PARAMETER: template-path" && exit 1
          [ ! -f "$templatePath" ] && echo "INVALID PARAMETER: template-path - \"$templatePath\" is not a file." && exit 1
          ;;
      esac
      [ -z "$ConfigBucket" ] && ConfigBucket=${defaults[ConfigBucket]}
      [ -z "$KcImage" ] && KcImage=${defaults[KcImage]}
      [ -z "$CoreImage" ] && CoreImage=${defaults[CoreImage]}
      [ -z "$PortalImage" ] && PortalImage=${defaults[PortalImage]}
      [ -z "$PdfImage" ] && PdfImage=${defaults[PdfImage]}
      [ -z "$EC2InstanceType" ] && EC2InstanceType=${defaults[EC2InstanceType]}
      [ -z "$Landscape" ] && Landscape=${defaults[Landscape]}
      templateDir=$(dirname $templatePath)
      templateName=$(echo $templatePath | grep -oP '[^/]+$')
      bucketPath="$(getBucketPath)"
      ;;
    refresh)
      [ -z "$stackName" ] && echo "MISSING PARAMETER: stack-name" && exit 1
      [ -z "$logicalResourceId" ] && echo "MISSING PARAMETER: logical-resource-id" && exit 1
      ;;
  esac

  bucketUrl="$(echo $bucketPath | sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//')"    

  if [ "${printVariables,,}" == "true" ] ; then
    echo "task=$task"
    echo "templatePath=$templatePath"
    echo "templateDir=$templateDir"
    echo "templateName=$templateName"
    echo "templateType=$templateType"
    echo "bucketPath=$bucketPath"
    echo "bucketUrl=$bucketUrl"
    echo "stackName=$stackName"
    echo "ConfigBucket"=$ConfigBucket
    echo "KcImage"=$KcImage
    echo "CoreImage"=$CoreImage
    echo "PortalImage"=$PortalImage
    echo "PdfImage"=$PdfImage
    echo "EC2InstanceType"=$EC2InstanceType
    echo "Landscape"=$Landscape
    echo " "
  fi
}

examples() {
  cat <<EOF
    EXAMPLES:

    sh $templatePath/scripts/ecs.sh \\
      --task validate \\
      --template-path $templatePath/test/ec2-test-2.yaml \\

    sh $templatePath/scripts/ecs.sh \\
      --task upload

    sh $templatePath/scripts/ecs.sh \\
      --task create \\
      --stack-name kuali-ec2-for-ecs-test \\
      --template-path $templatePath/test/ec2-test-2.yaml \\
      --bucket-path s3://kuali-research-ec2-setup/ecs/cloudformation/test \\
      --config-bucket kuali-research-ec2-setup \\
      --docker-image-tag 2001.0040 \\
      --docker-repository-uri 730096353738.dkr.ecr.us-east-1.amazonaws.com/core \\
      --ec2-instance-type t2.small \\
      --landscape sb

    sh $templatePath/scripts/ecs.sh \\
      --task update \\
      --template-path $templatePath/test/ec2-test-2.yaml \\
      --stack-name kuali-ec2-for-ecs-test

EOF
}


parseargs $@

case "$task" in
  validate)
    echo "Validate the specified template(s)"
    ecsValidate
    ;;
  upload)
    echo "Upload the specified template(s) to s3 bucket"
    ecsUpload
    ;;
  create)
    echo "Creating stack: $stackName..."
    ecsStackAction "create-stack"
    ;;
  update)
    echo "Performing an update to stack: $stackName..."
    ecsStackAction "update-stack"
    ;;
  delete)
    echo "Deleting stack: $stackName..."
    ecsStackAction "delete-stack"
    ;;
  refresh)
    echo "Perform a metadata refresh"
    ecsMetaRefresh
    ;;
  examples)
    examples
    ;;
  parseargs)
    echo " "
    ;;
  *)
    if [ -n "$task" ] ; then
      echo "INVALID PARAMETER: No such task: $task"
    else
      echo "MISSING PARAMETER: task"
    fi
    exit 1
    ;;
esac
