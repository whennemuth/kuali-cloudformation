#!/bin/bash

source ./common-functions.sh

# Transfer repositories from ecr in one account to ecr in another account
migrate() {
  # Validate parameters
  [ -z "$(echo "$SOURCE_ACCOUNT_ID" | grep -P '\d+')" ] && echo "Missing/invalid source account ID" && exit 1
  [ -z "$(echo "$TARGET_ACCOUNT_ID" | grep -P '\d+')" ] && echo "Missing/invalid target account ID" && exit 1

  echo "Transferring repositories from account: $SOURCE_ACCOUNT_ID to account: $TARGET_ACCOUNT_ID"

  # Log into both source and target registries
  $(aws --profile=$SOURCE_PROFILE ecr get-login --no-include-email --region us-east-1)
  $(aws --profile=$TARGET_PROFILE ecr get-login --no-include-email --region us-east-1)
  
  local pulled=0
  local pushed=0
  for sourceImg in $(listRemoteImages $SOURCE_PROFILE) ; do

    # Establish the name the image should have in the target registry
    local targetImg="$( \
      echo "$sourceImg" | \
      sed 's/\//\/kuali-/' | \
      sed 's/'$SOURCE_ACCOUNT_ID'/'$TARGET_ACCOUNT_ID'/g')"

    # Remove the source image if it exists locally already.
    if [ -n "$(docker images $sourceImg -q)" ] ; then
      docker rmi -f $sourceImg
      docker rmi -f $(docker images --filter dangling=true -q) 2> /dev/null
    fi

    # Pull the image from the source registry
    echo "Pulling $sourceImg..."
    docker pull $sourceImg
    [ $? -eq 0 ] && ((pulled++))

    # Push the image to the target registry
    echo "Pushing $targetImg..."
    docker tag $sourceImg $targetImg
    pushImage $targetImg
    [ $? -eq 0 ] && ((pushed++))

    # Remove the image locally. If there are a lot of images to migrate, you could eventually use up a lot of space if you don't do this.
    echo "Cleaning up..."
    docker rmi -f $sourceImg
    docker rmi -f $targetImg
    docker rmi -f $(docker images --filter dangling=true -q) 2> /dev/null
  done

  echo "Number of images pulled: $pulled"
  echo "Number of images pushed: $pulled"
}


listRemoteImages() {
  local profile="$1"
  for repo in $(aws ecr describe-repositories \
    --profile=$profile \
    --output text \
    --query "repositories[*].{URI:repositoryUri}" | dos2unix \
  ) ; do
    local line=1
    local name=$(echo $repo | cut -d'/' -f2)
    for desc in $(aws ecr describe-images \
      --repository-name $name \
      --profile=$profile \
      --output text \
      --query "sort_by(imageDetails, &imagePushedAt)[*].{NAME:repositoryName, VERSION:imageTags[0]}" | dos2unix
    ) ; do
      if [ $line -eq 2 ] ; then
        local version="$desc"
        # Filter out certain repositories that we don't care about
        if [ "${name:0:3}" != 'coi' ] && [ "${name,,}" != 'hello-world' ] ; then
          # Filter out "Orphaned" images
          if [ -n "version" ] && [ "${version,,}" != "none" ] ; then
            echo "$repo:$version"
          fi
        fi
        ((line--))
      else
        ((line++))
      fi
    done
  done
}


# Push the specified image to the registry and repository indicated in its name,
# creating the repository first if it doesn't already exist in the registry.
pushImage() {
  local image="$1"
  local repoName=$(echo $image | cut -d'/' -f2 | cut -d':' -f1)
  if [ -z "$targetRepos" ] ; then
    targetRepos=$(aws \
      --profile $TARGET_PROFILE ecr describe-repositories \
      --output text \
      --query "repositories[*].{NAME:repositoryName}")
  fi
  local repoExists=""
  for name in $targetRepos ; do
    if [ "$name" == "$repoName" ] ; then
      repoExists="$name"
      break;
    fi
  done

  if [ ! "$repoExists" ] ; then
    aws --profile $TARGET_PROFILE ecr create-repository --repository-name $repoName
  fi

  docker push $image
}

test() {
  echo "No tests"
}


[ $# -eq 0 ] && echo "Task parameter missing!" && exit 1
task="${1,,}"
shift
parseArgs $@

case $task in
  migrate)
    migrate ;;
  list)
    list ;;
  test)
    test ;;
esac

