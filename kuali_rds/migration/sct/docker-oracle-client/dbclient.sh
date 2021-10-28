#!/bin/bash

set -a 

source ../../../../scripts/common-functions.sh

if [ -n "$(echo "$nv" | grep -i 'raw_sql=')" ] ; then
  # One of the name/value pairs might be raw sql, which will have spaces in it.
  # If so, encode the pair so that it has no spaces and parseArgs will not break.
  # NOTE: The code that consumes the raw sql value will need to decode it first.
  tempArgs=""
  for nv in "$@" ; do
    lower="${nv,,}"
    if [ "${nv:0:8}" == 'raw_sql=' ] ; then
      tempArgs="$tempArgs encoded_sql=$(echo "$nv" | cut -d'=' -f2- | base64 -w 0)"
    else
      tempArgs="$tempArgs $nv"
    fi
  done
  sh dbclient.sh $tempArgs
  exit 0
  # eval "parseArgs silent=true default_profile=true $tempArgs"
else 
  parseArgs silent=true default_profile=true $@
fi


getPwdForMount() {
  local dir="$1"
  local subdir="$2"
  if [ -z "$dir" ] ; then
    dir=$(pwd)
  elif [ -n "$subdir" ] ; then
    dir=$(pwd)/$subdir
  fi
  if windows ; then
    echo $(echo $dir | sed 's/\/c\//C:\//g' | sed 's/\//\\\\/g')
  else
    echo "$dir"
  fi
}

getPwdForDefaultInputMount() {
   getPwdForMount $(pwd)/input/
}
getPwdForDefaultOutputMount() {
   getPwdForMount $(pwd)/output/
}
getPwdForSctScriptMount() {
  getPwdForMount $(dirname $(pwd))/sql/$LANDSCAPE/
}
getPwdForGenericSqlMount() {
  getPwdForMount $(pwd)/docker/sql/
}

build() {
  [ ! -f ../../../jumpbox/tunnel.sh ] && echo "Cannot find tunnel.sh" && exit 1
  [ ! -f ../../../../scripts/common-functions.sh ] && echo "Cannot find common-functions.sh" && exit 1
  cp ../../../jumpbox/tunnel.sh ./docker/bash/
  cp ../../../../scripts/common-functions.sh ./docker/bash/
  docker build -t oracle/sqlplus .
  rm -f ./docker/bash/tunnel.sh
  rm -f ./docker/bash/common-functions.sh
  echo "Removing dangling images..."
  docker rmi $(docker images --filter dangling=true -q) 2> /dev/null
}

run() {
  [ -z "$(docker images oracle/sqlplus -q)" ] && build
  [ -z "$(docker images oracle/sqlplus -q)" ] && echo "ERROR! Failed to build image oracle/sqlplus." && exit 1
  [ ! -d 'input' ] && mkdir input
  [ ! -d 'output' ] && mkdir output
  [ -z "$INPUT_MOUNT" ] && INPUT_MOUNT=$(getPwdForDefaultInputMount)
  [ -z "$OUTPUT_MOUNT" ] && OUTPUT_MOUNT=$(getPwdForDefaultOutputMount)

  docker run \
    -ti \
    --rm \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $OUTPUT_MOUNT:/tmp/output/ \
    oracle/sqlplus \
    $@
}

shell() {
  [ -z "$(docker images oracle/sqlplus -q)" ] && build
  [ -z "$(docker images oracle/sqlplus -q)" ] && echo "ERROR! Failed to build image oracle/sqlplus." && exit 1
  [ ! -d 'input' ] && mkdir input
  [ ! -d 'output' ] && mkdir output
  [ -z "$INPUT_MOUNT" ] && INPUT_MOUNT=$(getPwdForDefaultInputMount)
  [ -z "$OUTPUT_MOUNT" ] && OUTPUT_MOUNT=$(getPwdForDefaultOutputMount)

  docker run \
    -ti \
    --rm \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $OUTPUT_MOUNT:/tmp/output/ \
    --entrypoint bash \
    oracle/sqlplus
}


# Call stored procs that can disable/enable constraints and triggers.
# Disable these before migrating, enable after migrating.
toggleConstraintsAndTriggers() {
  [ -z "$TOGGLE_CONSTRAINTS" ] && TOGGLE_CONSTRAINTS="DISABLE"
  [ -z "$TOGGLE_TRIGGERS" ] && TOGGLE_TRIGGERS="DISABLE"
  local encoded_sql=""
  local schemas='KCOEUS KCRMPROC KULUSERMAINT SAPBWKCRM SAPETLKCRM SNAPLOGIC'

  if [ "${TOGGLE_CONSTRAINTS,,}" != "none" ] ; then
    for schema in $schemas ; do
      [ -n "$encoded_sql" ] && encoded_sql="$encoded_sql@"
      encoded_sql="$encoded_sql$(echo "execute toggle_constraints('$schema', 'FK', '$TOGGLE_CONSTRAINTS')" | base64 -w 0)"
    done
  fi

  if [ "${TOGGLE_CONSTRAINTS,,}" != "none" ] ; then
    for schema in $schemas ; do
      [ -n "$encoded_sql" ] && encoded_sql="$encoded_sql@"
      encoded_sql="$encoded_sql$(echo "execute toggle_constraints('$schema', 'PK', '$TOGGLE_CONSTRAINTS')" | base64 -w 0)"
    done
  fi

  if [ "${TOGGLE_TRIGGERS,,}" != "none" ] ; then
    for schema in $schemas ; do
      [ -n "$encoded_sql" ] && encoded_sql="$encoded_sql@"
      encoded_sql="$encoded_sql$(echo "execute toggle_triggers('$schema', '$TOGGLE_TRIGGERS')" | base64 -w 0)"
    done
  fi

  run $@ encoded_sql="$encoded_sql" "log_path=toggle_constraints_triggers.log"
}

checkLandscape() {
  if [ -z "$LANDSCAPE" ] ; then
    echo "Missing landscape parameter!"
    exit 1
  fi
}

checkAwsCredentials() {
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] ; then
    echo "Missing aws access key and/or secret access key"
    exit 1
  fi
}

# Run all numbered sql files in directory indicated by the landscape, starting from the indicated numeric prefix.
# Example: In running all scripts, an error occurred on the 6th one. Correct error and rerun with start_at=6 added.
runFrom() {
  echo "Running meta data creation scripts starting at number $START_AT..."
  local files_to_run=""
  for (( n=$START_AT; n<=20; n++ )) ; do
    local x=$([ $n -lt 10 ] && echo "0$n" || echo $n)
    local file="$(ls -1 $(getPwdForSctScriptMount) | grep -P '^'$x'\..+\.sql$')";
    if [ -n "$file" ] ; then
      [ -n "$files_to_run" ] && files_to_run="$files_to_run,$file" || files_to_run=$file
    fi
  done
  run $@ files_to_run=$files_to_run
}

task="$1"

case "$task" in
  build) 
    build ;;
  run)
    if [ -n "$tempArgs" ] ; then
      run $tempArgs
    else
      run $@
    fi
    ;;
  rerun)
    build && run $@ ;;
  shell)
    shell ;;
  get-mount)
    checkLandscape
    getPwdForDefaultInputMount
    getPwdForSctScriptMount
    getPwdForGenericSqlMount
    ;;

  run-sct-scripts)
    checkLandscape
    checkAwsCredentials
    INPUT_MOUNT="$(getPwdForSctScriptMount)"
    if [ -n "$(echo "$START_AT" | grep -P '^\d+$')" ] ; then
      runFrom $@
    else
      echo 'Running all meta data creation scripts...'
      run $@ files_to_run=all
    fi
    [ $? -gt 0 ] && echo "Error code: $?, Cancelling..." && exit 1
    echo 'Creating constraint and trigger toggling procedures...' 
    run $@ files_to_run=create_toggle_constraints.sql,create_toggle_triggers.sql log_path=create_toggling.log
    [ $? -gt 0 ] && echo "Error code: $?, Cancelling..." && exit 1
    toggleConstraintsAndTriggers $@
    echo 'FINISHED (next step is data migration).'
    ;;
  toggle-constraints-triggers)
    toggleConstraintsAndTriggers $@ ;;
  update-sequences)
    if [ -n "$SEQUENCE_TASK" ] ; then
      sh bash/update.sequences.sh $@ sequence_task=$SEQUENCE_TASK
    else
      sh bash/update.sequences.sh $@ sequence_task=report-raw-create legacy=true
      sh bash/update.sequences.sh $@ sequence_task=report-sql-create legacy=true
      sh bash/update.sequences.sh $@ sequence_task=report-sql-upload
      sh bash/update.sequences.sh $@ sequence_task=resequence
    fi
    ;;
  table-counts)
    run $@ files_to_run=inventory.sql log_path=source-counts.log ;;
  compare-table-counts)
    INPUT_MOUNT=$(getPwdForGenericSqlMount)
    run $@ files_to_run=inventory.sql log_path=source-counts.log legacy=true
    run $@ files_to_run=inventory.sql log_path=target-counts.log legacy=false
    source bash/compare.row.counts.sh
    compareTableRowCounts source-counts.log target-counts.log ;;
  test)
    INPUT_MOUNT=$(getPwdForGenericSqlMount)
    run $@ files_to_run=inventory.sql log_path=target-counts.log legacy=false ;;
    # compareTableRowCounts source-counts.log target-counts.log ;;
esac