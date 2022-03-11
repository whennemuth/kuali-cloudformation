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

[ "$DEBUG" == 'true' ] && set -x

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
processMounts() {
  if [ -z "$INPUT_MOUNT" ] ; then
    INPUT_MOUNT=$(getPwdForDefaultInputMount)
  else
    INPUT_MOUNT=$(getPwdForMount $INPUT_MOUNT)
  fi
  if [ -z "$OUTPUT_MOUNT" ] ; then
    OUTPUT_MOUNT=$(getPwdForDefaultOutputMount)
  else
    OUTPUT_MOUNT=$(getPwdForMount $OUTPUT_MOUNT)
  fi
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
  processMounts

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
  processMounts

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

checkBaseline() {
  if [ -z "$BASELINE" ] ; then
  cat <<EOF
  Required parameter missing: BASELINE
  A baseline landscape is required to identify and locate parameters for the legacy oracle database
EOF
  exit 1
  fi
}

checkAwsCredentials() {
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] ; then
    echo "Required parameter(s) missing: AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY"
    exit 1
  fi
}

updateSequences() {

  checkDbOrAwsParmCombos() {
    local prefix="${1,,}"
    local prefix_="${prefix^^}_"
    [ -z "$prefix" ] && prefix_=''
    local valid='true'
    dbParmsIncomplete() {
      eval "local host="\${${prefix_}DB_HOST}""
      eval "local user="\${${prefix_}DB_USER}""
      eval "local port="\${${prefix_}DB_PORT}""
      eval "local pswd="\${${prefix_}DB_PASSWORD}""
      eval "local sid="\${${prefix_}DB_SID}""
      ([ -z "$host" ] || [ -z "$user" ] || [ -z "$port" ] || [ -z "$sid" ] || [ -z "$pswd" ]) && true || false
    }
    awsParmsIncomplete() {
      eval "local id="\${${prefix_}AWS_ACCESS_KEY_ID}""
      eval "local key="\${${prefix_}AWS_SECRET_ACCESS_KEY}""
      [ "$prefix" == 'legacy' ] && export PARM3='BASELINE'
      [ "$prefix" == 'target' ] && export PARM3='LANDSCAPE'
      [ -z "$PARM3" ] && P3='N/A' || eval "P3="\${$PARM3}""
      ([ -z "$id" ] || [ -z "$key" ] || [ -z "$P3" ]) && true || false
    }
    missingParms() {
      if dbParmsIncomplete && awsParmsIncomplete ; then true; else false; fi
    }
    if missingParms ; then
      local valid='false'
      cat <<EOF

      REQUIRED ${prefix^^} PARAMETER(S) MISSING!
      One of two sets of parameters must be provided:
      1)
        - ${PARM3:-"N/A"}
        - ${prefix_}AWS_ACCESS_KEY_ID
        - ${prefix_}AWS_SECRET_ACCESS_KEY
        or...
      2)
        - ${prefix_}DB_HOST
        - ${prefix_}DB_USER
        - ${prefix_}DB_PORT
        - ${prefix_}DB_SID
        - ${prefix_}DB_PASSWORD

EOF
    fi
    [ "$valid" == 'true' ] && true || false
  }

  checkLegacyAndTargetComboParms() {
    local valid='true'
    ! checkDbOrAwsParmCombos 'legacy' && valid='false'
    ! checkDbOrAwsParmCombos 'target' && valid='false'
    [ $valid == 'true' ] && true || false
  }


  # The AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY values will have been provided for both the "legacy" aws account
  # and a newer "target" account. Strip out the id and key pair for "target" if "legacy is specified" and vice versa.
  # This will "filter" down the arg list from having 4 "AWS_..." values to 2.
  filterArgs() {
    local type="$1"
    local args=""
    shift
    for nv in $@ ; do
      if [ -n "$(grep '=' <<< $nv)" ] ; then
        local name="$(echo $nv | cut -d'=' -f1)"
        local value="$(echo $nv | cut -d'=' -f2-)"
        case $type in
          target)
            [ "${name,,}" == 'legacy_aws_access_key_id' ] && continue 
            [ "${name,,}" == 'legacy_aws_secret_access_key' ] && continue 
            [ "${name,,}" == 'target_aws_access_key_id' ] && args="$args aws_access_key_id=$value" && continue
            [ "${name,,}" == 'target_aws_secret_access_key' ] && args="$args aws_secret_access_key=$value" && continue
            ;;
          legacy)
            [ "${name,,}" == 'target_aws_access_key_id' ] && continue 
            [ "${name,,}" == 'target_aws_secret_access_key' ] && continue 
            [ "${name,,}" == 'legacy_aws_access_key_id' ] && args="$args aws_access_key_id=$value" && continue
            [ "${name,,}" == 'legacy_aws_secret_access_key' ] && args="$args aws_secret_access_key=$value" && continue
            ;;
        esac
      fi
      args="$args $nv"
    done
    echo "$args"
  }

  if [ -n "$SEQUENCE_TASK" ] ; then
    case "$SEQUENCE_TASK" in
      report-raw-create)
        ! checkDbOrAwsParmCombos && exit 1
        sh bash/update.sequences.sh $(filterArgs 'legacy' $@) sequence_task=report-raw-create legacy=true
        ;;
      report-sql-create)
        sh bash/update.sequences.sh $@ sequence_task=report-sql-create legacy=true
        ;;
      report-sql-upload)        
        ! checkDbOrAwsParmCombos && exit 1
        sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=report-sql-upload
        ;;
      resequence)
        ! checkDbOrAwsParmCombos && exit 1
        sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=resequence
        ;;
    esac
  else
    ! checkLegacyAndTargetComboParms && exit 1
    sh bash/update.sequences.sh $(filterArgs 'legacy' $@) sequence_task=report-raw-create legacy=true && \
    sh bash/update.sequences.sh $@ sequence_task=report-sql-create legacy=true && \
    sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=report-sql-upload && \
    sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=resequence
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
    updateSequences $@
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