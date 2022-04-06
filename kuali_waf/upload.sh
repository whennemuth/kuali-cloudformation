#!/bin/bash
source ../scripts/common-functions.sh

declare TEMPLATE_BUCKET=${TEMPLATE_BUCKET:-"kuali-conf"}
declare -A defaults=(
  [TEMPLATE_BUCKET_PATH]='s3://'$TEMPLATE_BUCKET'/cloudformation/kuali_waf'
  [TEMPLATE_PATH]='.'
)

if ! isCurrentDir "kuali_waf" ; then
  echo "You must run this script from the kuali_waf subdirectory!"
  exit 1
fi

parseArgs $@

setDefaults

uploadStack silent 

