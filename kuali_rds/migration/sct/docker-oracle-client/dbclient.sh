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
  cp ../../../jumpbox/tunnel.sh ./bin/bash/
  cp ../../../../scripts/common-functions.sh ./bin/bash/
  docker build -t oracle/sqlplus .
  rm -f ./bin/bash/tunnel.sh
  rm -f ./bin/bash/common-functions.sh
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

test() {
  SCRIPT="TESTING"
  cat <<-EOF
    WHENEVER SQLERROR EXIT SQL.SQLCODE;
    SET FEEDBACK OFF
    $(
      i=1
      for f in $(ls -1 ../sql/ci-example/*.sql | grep -o -e '[^/]*$') ; do
        log=$(echo $f | sed 's/\.sql/\.log/')
        printf \\n'    spool /tmp/output/'$log
        printf \\n'    @'$f
        ((i++))
      done
    )
    spool off;
    exit;
EOF
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
  run-sct-scripts)
    INPUT_MOUNT="$(getPwdForSctScriptMount)"
    run $@ files_to_run=all ;;
  compare-table-counts)
    run $@ legacy=true  files_to_run=inventory.sql log_name=source-counts.log
    run $@ legacy=false files_to_run=inventory.sql log_name=target-counts.log
    compareCounts ;;
  test)
    test ;;
esac