#!/bin/bash

# --------------------------------------------------------------------------------------------------------------
# PURPOSE: Use this script to move the contents of one s3 bucket in a source account to an s3 bucket in a 
# target account.
# Main function:
#    migrate()
#    Args: (case insensitive)
#       source_bucket: The name of the bucket to copy contents from
#       target_bucket: The name of the bucket to copy contents into
#       source_profile: The aws profile for cli access to commands against the source account
#       target_profile: The aws profile for cli access to commands against the target account
#       dryrun: print out each s3 cp command, but do not execute it.
#    Example:
#       bash migrate.ecr.sh migrate \
#         source_bucket=kuali-research-ec2-setup \
#         target_bucket=kuali-conf \
#         source_profile= \ # leave empty to use default profile
#         target_profile=infnprd \
#         dryrun=true
#    NOTE: call with bash, not sh
# --------------------------------------------------------------------------------------------------------------

source ./common-functions.sh

# Key value pairs:
# key: A substring to find in the path of a file in a source s3 bucket
# value: The replacement for the substring to form a new path to copy the file to in the target bucket.
declare -A newpaths=(
  ['\/kuali\/main\/config\/']='\/kc\/'
  ['\/kuali\/tls\/certs\/']='\/kc\/'
  ['\/kuali\/tls\/private\/']='\/kc\/'
  ['\/kuali\/']='\/kc\/'
)

# An array of filters:
# If any part of the path of a file in the source s3 bucket matches any one of these array values,
# then that file will not be copied to the target bucket.
omitpaths=(
  '/ssl/' 
  '/apache/'
  'cloudformation/'
  'coeus-webapp-2001.0040.war'
  'misc/'
  'kc-config.xml.old'
  'ecr.credentials.cfg'
)

# MAIN FUNCTION:
migrate() {
  if ! bucketExistsInThisAccount $TARGET_BUCKET $TARGET_PROFILE ; then
    if askYesNo "$TARGET_BUCKET does not exist. Create?" ; then
      aws --profile=$TARGET_PROFILE s3 mb s3://$TARGET_BUCKET
    else
      exit 0
    fi
  fi

  aws --profile=$SOURCE_PROFILE s3 ls --recursive s3://$SOURCE_BUCKET \
    | awk '{if ($3 != "0") print $4}' \
    | omitPaths \
    | convertPaths \
    | execCpCommand
}

# Replace any segment of the provided text that matches any key of newpaths with the value of that key(s).
convertPaths() {
  convertPath() {
    if [ $# -eq 1 ] ; then
      convertPath 0 "$1"
    elif [ $1 -eq ${#newpaths[@]} ] ; then
      echo "$2"
    else
      local index=$1
      local path=$2
      local keys=(${!newpaths[@]})
      local key=${keys[$index]}
      local value=${newpaths[$key]}
      local newpath=$(echo "$path" | sed 's/'$key'/'$value'/')
      convertPath $((++index)) "$newpath"
    fi
  }
  while read path; do
    printf "$path " && convertPath "$path"
  done
}

# echo only those lines of the piped input that do no have any member of the omitpaths array as a substring.
omitPaths() {
  while read line; do
    for omit in ${omitpaths[@]} ; do
      if [ -n "$(echo "$line" | grep ''$omit'')" ] ; then
        continue 2
      fi
    done
    echo $line
  done
}

# Execute each line of the piped input as a separate command. Each command executed copies one file
# from one source s3 bucket to a target s3 bucket.
execCpCommand() {
  while read fileset; do
    local sourcefile="$(echo $fileset | awk '{print $1}')"
    local targetfile="$(echo $fileset | awk '{print $2}')"
    local cmd=$(
      cat <<EOF
        aws \
          --profile=$SOURCE_PROFILE \
          s3 cp s3://$SOURCE_BUCKET/$sourcefile - | \
        aws \
          --profile=$TARGET_PROFILE \
          s3 cp - s3://$TARGET_BUCKET/$targetfile
EOF
    )
    echo "$cmd" | sed 's/ \+/ /g'
    [ -z "$DRYRUN" ] && eval "$cmd"
    [ $? -gt 0 ] && echo "$cmd" >> failures.log
  done
}

[ $# -eq 0 ] && echo "Task parameter missing!" && exit 1
task="${1,,}"
shift
parseArgs $@

case $task in
  migrate)
    migrate ;;
  test)
    cat <<EOF | convertPaths
    one/kuali/tls/certs/
    two/kuali/tls/private/
    three/kuali/tls/certs/myfile.txt
EOF
    ;;
esac

