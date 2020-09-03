#!/bin/bash

source ../../../../scripts/common-functions.sh

parseArgs silent=true default_profile=true $@

getPwdForMount() {
  local dir="$1"
  [ -z "$dir" ] && dir=$(pwd)
  if windows ; then
    echo $(echo $dir | sed 's/\/c\//C:\//g' | sed 's/\//\\\\/g')\\\\
  else
    echo "$dir/"
  fi
}

getPwdForSctScriptMount() {
  getPwdForMount $(dirname $(pwd))/sql/$LANDSCAPE
}

build() {
  [ ! -f ../../../jumpbox/tunnel.sh ] && echo "Cannot find tunnel.sh" && exit 1
  [ ! -f ../../../../scripts/common-functions.sh ] && echo "Cannot find common-functions.sh" && exit 1
  cp ../../../jumpbox/tunnel.sh .
  cp ../../../../scripts/common-functions.sh .
  docker build -t oracle/sqlplus .
  rm -f tunnel.sh
  rm -f common-functions.sh
  echo "Removing dangling images..."
  docker rmi $(docker images --filter dangling=true -q) 2> /dev/null
}

run() {
  [ -z "$(docker images oracle/sqlplus -q)" ] && build
  [ ! -d 'input' ] && mkdir input
  [ ! -d 'output' ] && mkdir output
  [ -z "$INPUT_MOUNT" ] && INPUT_MOUNT=$(getPwdForMount)/input
  docker run \
    -ti \
    --rm \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $(getPwdForMount)/output:/tmp/output/ \
    oracle/sqlplus \
    $@
}

shell() {
  [ -z "$(docker images oracle/sqlplus -q)" ] && build
  [ ! -d 'input' ] && mkdir input
  [ ! -d 'output' ] && mkdir output
  [ -z "$INPUT_MOUNT" ] && INPUT_MOUNT=$(getPwdForMount)/input
  docker run \
    -ti \
    --rm \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $(getPwdForMount)/output:/tmp/output/ \
    --entrypoint bash \
    oracle/sqlplus
}

compareCounts() {
  local source="output/source-counts.log"
  local target="output/target-counts.log"
  echo "RESUME NEXT: complete this function"
}

task="$1"

case "$task" in
  build) 
    build ;;
  run)
    run $@ ;;
  rerun)
    build && run $@ ;;
  shell)
    shell ;;
  run-inputs)
    run $@ inputs=true ;;
  run-sct-scripts)
    INPUT_MOUNT="$(getPwdForSctScriptMount)"
    run $@ inputs=true ;;
  compare-table-counts)
    run $@ legacy=true  script=inventory.sql log_name=source-counts.log
    run $@ legacy=false script=inventory.sql log_name=target-counts.log
    compareCounts ;;
esac