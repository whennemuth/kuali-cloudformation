#!/bin/bash
source ../scripts/common-functions.sh

declare -A defaults=(
  [TEMPLATE_BUCKET_PATH]='s3://kuali-conf/cloudformation/kuali_waf'
  [TEMPLATE_PATH]='.'
)

if ! isCurrentDir "kuali_waf" ; then
  echo "You must run this script from the kuali_waf subdirectory!"
  exit 1
fi

parseArgs $@

setDefaults

uploadStack silent 

