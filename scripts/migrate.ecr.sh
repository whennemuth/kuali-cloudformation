#!/bin/bash

# --------------------------------------------------------------------------------------------------------------
# PURPOSE: Use this script to copy all repositories in an aws source elastic container registry of a source
# account to the elastic container registry in a target account.
# main function: 
#    migrate()
#    Args: (case insensitive)
#       source_profile: The aws profile for cli access to commands against the source account
#       target_profile: The aws profile for cli access to commands against the target account
#       single_image: [optional] If included, limits migration to a single image (not all images)
#       dryrun: print out each s3 cp command, but do not execute it.
#    Example:
#       sh migrate.ecr.sh migrate \
#         source_profile=legacy \
#         target_profile=infnprd \
#         dryrun=true
# 
#       sh migrate.ecr.sh migrate \
#         source_profile=legacy \
#         target_profile=infnprd \
#         single_image=core:2011.0032
#         dryrun=true
# --------------------------------------------------------------------------------------------------------------

source ./common-functions.sh

AWS_REGION='us-east-1'

# Transfer repositories from ecr in one account to ecr in another account
migrate() {
  # Validate parameters
  [ -z "$SOURCE_PROFILE" ] && echo "Missing/invalid source profile" && exit 1
  [ -z "$TARGET_PROFILE" ] && echo "Missing/invalid target profile" && exit 1

  local sourceAccountID="$(aws --profile=$SOURCE_PROFILE sts get-caller-identity --output text --query 'Account')"
  local targetAccountID="$(aws --profile=$TARGET_PROFILE sts get-caller-identity --output text --query 'Account')"

  [ -z "$(echo "$sourceAccountID" | grep -P '\d+')" ] && echo "Cannot determine source account ID" && exit 1
  [ -z "$(echo "$targetAccountID" | grep -P '\d+')" ] && echo "Cannot determine target account ID" && exit 1

  if [ -n "$SINGLE_IMAGE" ] ; then
    if [ -z "$(echo $SINGLE_IMAGE | grep '.dkr.ecr.')" ] ; then
      SINGLE_IMAGE="$sourceAccountID.dkr.ecr.$AWS_REGION.amazonaws.com/$SINGLE_IMAGE"
    fi
  fi

  echo "Transferring repositories from account: $sourceAccountID to account: $targetAccountID"

  # Log into both source and target registries
  if ecrGetLoginDeprecated ; then
    aws --profile=$SOURCE_PROFILE ecr get-login-password \
      | docker login --username AWS --password-stdin $sourceAccountID.dkr.ecr.$AWS_REGION.amazonaws.com
    if ! dryrun ; then
      aws --profile=$TARGET_PROFILE ecr get-login-password \
        | docker login --username AWS --password-stdin $targetAccountID.dkr.ecr.$AWS_REGION.amazonaws.com
    fi
  else
    $(aws --profile=$SOURCE_PROFILE ecr get-login --no-include-email --region $AWS_REGION)
    if ! dryrun ; then
      $(aws --profile=$TARGET_PROFILE ecr get-login --no-include-email --region $AWS_REGION)
    fi
  fi

  local pulled=0
  local pushed=0
  for sourceImg in $(listRemoteImages $SOURCE_PROFILE) ; do

    # Establish the name the image should have in the target registry (prepend "kuali-" and change account number)
    local targetImg="$( \
      echo "$sourceImg" | \
      sed 's/\//\/kuali-/' | \
      sed 's/'$sourceAccountID'/'$targetAccountID'/g')"

    # Remove the source image if it exists locally already.
    if ! dryrun ; then
      if [ -n "$(docker images $sourceImg -q)" ] ; then
        docker rmi -f $sourceImg
        docker rmi -f $(docker images --filter dangling=true -q) 2> /dev/null
      fi
    fi

    # Pull the image from the source registry
    echo "Pulling $sourceImg..."
    if dryrun ; then
      echo "DRYRUN: docker pull $sourceImg"
    else
      docker pull -q -a $sourceImg
    fi
    [ $? -eq 0 ] && ((pulled++))

    # Push the image to the target registry
    if dryrun ; then
      echo "DRYRUN: Pushing $targetImg..."
      continue
    else
      echo "Pushing $targetImg..."
      docker tag $sourceImg $targetImg
      pushImage $targetImg
    fi
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

# Print out all images in all repositories of the elastic container service for the account indicated by profile.
listRemoteImages() {
  if [ -n "$SINGLE_IMAGE" ] ; then
    echo "$SINGLE_IMAGE"
    return 0
  fi
  local profile="$1"
  for repo in $(aws ecr describe-repositories \
    --profile=$profile \
    --output text \
    --query "repositories[*].{URI:repositoryUri}" | dos2unix \
  ) ; do
    local line=1
    local name=$(echo $repo | cut -d'/' -f2)
    if [ -n "$SINGLE_REPO" ] && [ "${name,,}" != "${SINGLE_REPO,,}" ] ; then
      continue;
    fi
    for desc in $(aws ecr describe-images \
      --repository-name $name \
      --profile=$profile \
      --output text \
      --query "sort_by(imageDetails, &imagePushedAt)[*].{NAME:repositoryName, VERSION:imageTags[0]}" | dos2unix
    ) ; do
      if [ $line -eq 2 ] ; then
        local version="$desc"
        # Filter out certain repositories that we don't care about
        # if [ "${name:0:3}" != 'coi' ] && [ "${name,,}" != 'hello-world' ] ; then
        if [ "${name,,}" != 'hello-world' ] ; then
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

dryrun() {
  [ "${DRYRUN,,}" == 'true' ] && true || false
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
    if [ -n "$PROFILE" ] ; then
      listRemoteImages $PROFILE
    else
      echo "Missing profile"
    fi
    ;;
  test)
    test ;;
esac

