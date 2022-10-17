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

# Return the value of either aws_access_key_id or aws_secret_access_key or aws_session_token for cli authentication.
# This assumes the variable is set in the environment and can simply be echoed out.
# If not, check if a name profile has been set for aws_profile (or profile) and use it in a lookup for the key or secret.
# If a prefix parameter is provided, prepend it to key, secret, or profile variable name(s) before echoing out result.
getAwsCredential() {
  local credtype="${1,,}"
  local prefix="${2^^}"
  [ -n "$prefix" ] && [ "${prefix: -1}" != '_' ] && prefix="${prefix}_"
  case "$credtype" in
    id|aws_access_key_id)
      local credname='aws_access_key_id'
      local varname="${prefix}${credname^^}"
      ;;
    key|aws_secret_access_key)
      local credname='aws_secret_access_key'
      local varname="${prefix}${credname^^}"
      ;;
    session|token|aws_session_token)
      local credname='aws_session_token'
      local varname="${prefix}${credname^^}"
      ;;
    *)
      return -1
      ;;
  esac

  local val="${!varname}"
  if [ -n "$val" ] ; then
    echo "$val"
  else
    local profileVarName="${prefix}AWS_PROFILE"
    local val=$(eval "aws --profile=${!profileVarName} configure get $credname" 2> /dev/null)
    if [ -z "$val" ] ; then
      local profileVarName="${prefix}PROFILE"
      local val=$(eval "aws --profile=${!profileVarName} configure get $credname" 2> /dev/null)
    fi
    echo "$val"
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

  removeProfileArg() {
    local args=()
    for arg in $@ ; do
      local arglower=${arg,,}
      [ "aws_profile=" == "${arglower:0:12}" ] && continue
      [ "profile=" == "${arglower:0:8}" ] && continue
      args=(${args[@]} $arg)
    done
    echo ${args[@]}
  }

  local cmd=$(cat <<EOF
  docker run \
    -ti \
    --rm \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $OUTPUT_MOUNT:/tmp/output/ \
    oracle/sqlplus \
    $(removeProfileArg $@)
EOF
  )
  echo $cmd
  eval $cmd
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
    -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
    -v $INPUT_MOUNT:/tmp/input/ \
    -v $OUTPUT_MOUNT:/tmp/output/ \
    --entrypoint bash \
    oracle/sqlplus
}



# If the script was called providing a named profile(s) instead of key and secret, set the key and secret from a lookup against the named
# profile (the docker container cannot be passed a profile, must be key and secret - not mounting the aws config/credentials file to the container)
checkAwsCredentials() {

  validateAwsCredentials() {
    local credtype="$1"
    local id="$2"
    local key="$3"
    local token="$4"
    
    if [ "${VALIDATE_CREDENTIALS,,}" == 'false' ] ; then
      return 0
    fi
    if [ -z "$id" ] || [ -z "$key" ] ; then
      local prefix="$credtype"
      [ "$prefix" == 'basic' ] && $prefix=""
      [ -n "$prefix" ] && prefix="${prefix^^}_"
      echo "Minimum required parameter(s) missing: ${prefix}AWS_ACCESS_KEY_ID and/or ${prefix}AWS_SECRET_ACCESS_KEY"
      exit 1
    fi

    (
      AWS_ACCESS_KEY_ID=$id
      AWS_SECRET_ACCESS_KEY=$key
      AWS_SESSION_TOKEN=$token
      local cid="$(aws sts get-caller-identity 2> /dev/null)"
      if [ $? -gt 0 ] || [ -z "$cid" ] ; then
        echo "The provided $credtype credentials do not give access. Check them and try again."
        exit 1
      else
        echo "The provided $credtype credentials passed validation."
      fi
    )

    [ $? -gt 0 ] && exit 1
  }

  local credtype=${1:-"basic"}
  case $credtype in
    basic)
      [ -z "$AWS_ACCESS_KEY_ID" ] && AWS_ACCESS_KEY_ID=$(getAwsCredential 'id')
      [ -z "$AWS_SECRET_ACCESS_KEY" ] && AWS_SECRET_ACCESS_KEY=$(getAwsCredential 'key')
      [ -z "$AWS_SESSION_TOKEN" ] && AWS_SESSION_TOKEN=$(getAwsCredential 'session')
      validateAwsCredentials $credtype $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $AWS_SESSION_TOKEN
      ;;
    legacy)
      [ -z "$LEGACY_AWS_ACCESS_KEY_ID" ] && LEGACY_AWS_ACCESS_KEY_ID=$(getAwsCredential 'id' 'legacy')
      [ -z "$LEGACY_AWS_SECRET_ACCESS_KEY" ] && LEGACY_AWS_SECRET_ACCESS_KEY=$(getAwsCredential 'key' 'legacy')
      [ -z "$LEGACY_AWS_SESSION_TOKEN" ] && LEGACY_AWS_SESSION_TOKEN=$(getAwsCredential 'session' 'legacy')
      validateAwsCredentials $credtype $LEGACY_AWS_ACCESS_KEY_ID $LEGACY_AWS_SECRET_ACCESS_KEY $LEGACY_AWS_SESSION_TOKEN
      ;;
    target)
      [ -z "$TARGET_AWS_ACCESS_KEY_ID" ] && TARGET_AWS_ACCESS_KEY_ID=$(getAwsCredential 'id' 'target')
      [ -z "$TARGET_AWS_SECRET_ACCESS_KEY" ] && TARGET_AWS_SECRET_ACCESS_KEY=$(getAwsCredential 'key' 'target')
      [ -z "$TARGET_AWS_SESSION_TOKEN" ] && TARGET_AWS_SESSION_TOKEN=$(getAwsCredential 'session' 'target')
      validateAwsCredentials $credtype $TARGET_AWS_ACCESS_KEY_ID $TARGET_AWS_SECRET_ACCESS_KEY $TARGET_AWS_SESSION_TOKEN
      ;;
  esac
}


# Call stored procs that can disable/enable constraints and triggers.
# Disable these before migrating, enable after migrating.
toggleConstraintsAndTriggers() {
  [ -z "$TOGGLE_CONSTRAINTS" ] && TOGGLE_CONSTRAINTS="DISABLE"
  [ -z "$TOGGLE_TRIGGERS" ] && TOGGLE_TRIGGERS="DISABLE"
  local encoded_sql=""
  local schemas='KCOEUS KCRMPROC KULUSERMAINT SAPBWKCRM SAPETLKCRM SNAPLOGIC'

  toggleConstraints() {
    constraintType="$1"
    if [ "${TOGGLE_CONSTRAINTS,,}" != "none" ] ; then
      for schema in $schemas ; do
        [ -n "$encoded_sql" ] && encoded_sql="$encoded_sql@"
        encoded_sql="$encoded_sql$(echo "execute toggle_constraints('$schema', '$constraintType', '$TOGGLE_CONSTRAINTS')" | base64 -w 0)"
      done
    fi
  }

  if [ TOGGLE_CONSTRAINTS == "DISABLE" ] ; then
    toggleConstraints 'FK'
    toggleConstraints 'PK'
  else
    toggleConstraints 'PK'
    toggleConstraints 'FK'
  fi


  if [ "${TOGGLE_TRIGGERS,,}" != "none" ] ; then
    for schema in $schemas ; do
      [ -n "$encoded_sql" ] && encoded_sql="$encoded_sql@"
      encoded_sql="$encoded_sql$(echo "execute toggle_triggers('$schema', '$TOGGLE_TRIGGERS')" | base64 -w 0)"
    done
  fi

  run $@ encoded_sql="$encoded_sql" "log_path=toggle_constraints_triggers.log"
}

validateLandscape() {
  if [ -z "$LANDSCAPE" ] ; then
    echo "Missing landscape parameter!"
    exit 1
  fi
}

validateBaseline() {
  if [ -z "$BASELINE" ] ; then
  cat <<EOF
  Required parameter missing: BASELINE
  A baseline landscape is required to identify and locate parameters for the legacy oracle database
EOF
  exit 1
  fi
}


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


# The AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and AWS_SESSION_TOKEN, if credentials are temporary) 
# values will have been provided for both the "legacy" aws account and a newer "target" account. 
# Strip out the id and key pair for "target" if "legacy is specified" and vice versa.
# This will "filter" down the arg list from having 6 "AWS_..." values to 3.
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
          [ "${name,,}" == 'legacy_aws_session_token' ] && continue
          [ "${name,,}" == 'legacy_aws_profile' ] && continue
          [ "${name,,}" == 'target_aws_access_key_id' ] && args="$args aws_access_key_id=$value" && continue
          [ "${name,,}" == 'target_aws_secret_access_key' ] && args="$args aws_secret_access_key=$value" && continue
          [ "${name,,}" == 'target_aws_session_token' ] && args="$args aws_session_token=$value" && continue
          if [ "${name,,}" == 'target_aws_profile' ] ; then
            local id="$(getAwsCredential 'id' 'target')"
            local key="$(getAwsCredential 'key' 'target')"
            local token="$(getAwsCredential 'token' 'target')"
            [ -n "$id" ] && id="aws_access_key_id=$id"
            [ -n "$key" ] && key="aws_secret_access_key=$key"
            [ -n "$token" ] && token="aws_session_token=$token"
            args="$args $id $key $token"
          fi
          ;;
        legacy)
          [ "${name,,}" == 'target_aws_access_key_id' ] && continue 
          [ "${name,,}" == 'target_aws_secret_access_key' ] && continue 
          [ "${name,,}" == 'target_aws_session_token' ] && continue 
          [ "${name,,}" == 'target_aws_profile' ] && continue
          [ "${name,,}" == 'legacy_aws_access_key_id' ] && args="$args aws_access_key_id=$value" && continue
          [ "${name,,}" == 'legacy_aws_secret_access_key' ] && args="$args aws_secret_access_key=$value" && continue
          [ "${name,,}" == 'legacy_aws_session_token' ] && args="$args aws_session_token=$value" && continue
          if [ "${name,,}" == 'legacy_aws_profile' ] ; then
            local id="$(getAwsCredential 'id' 'legacy')"
            local key="$(getAwsCredential 'key' 'legacy')"
            local token="$(getAwsCredential 'token' 'legacy')"
            [ -n "$id" ] && id="aws_access_key_id=$id"
            [ -n "$key" ] && key="aws_secret_access_key=$key"
            [ -n "$token" ] && token="aws_session_token=$token"
            args="$args $id $key $token"
          fi
          ;;
      esac
    fi
    args="$args $nv"
  done
  echo "$args"
}


updateSequences() {

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
    # set -x
    sh bash/update.sequences.sh $(filterArgs 'legacy' $@) sequence_task=report-raw-create legacy=true && \
    sh bash/update.sequences.sh $@ sequence_task=report-sql-create legacy=true && \
    sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=report-sql-upload && \
    sh bash/update.sequences.sh $(filterArgs 'target' $@) sequence_task=resequence
  fi
}

compareTableCounts() {
  ! checkLegacyAndTargetComboParms && exit 1
  run $(filterArgs 'legacy' $@) files_to_run=inventory.sql log_path=source-counts.log legacy=true
  run $(filterArgs 'target' $@) files_to_run=inventory.sql log_path=target-counts.log legacy=false
  source bash/compare.row.counts.sh
  compareTableRowCounts source-counts.log target-counts.log
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
    checkAwsCredentials
    shell
    ;;
  get-mount)
    validateLandscape
    getPwdForDefaultInputMount
    getPwdForSctScriptMount
    getPwdForGenericSqlMount
    ;;
  run-sct-scripts)
    validateLandscape
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
    checkAwsCredentials
    toggleConstraintsAndTriggers $@ ;;
  update-sequences)
    checkAwsCredentials 'legacy'
    checkAwsCredentials 'target'
    updateSequences $@
    ;;
  table-counts)
    checkAwsCredentials
    run $@ files_to_run=inventory.sql log_path=source-counts.log ;;
  compare-table-counts)
    INPUT_MOUNT=$(getPwdForGenericSqlMount)
    checkAwsCredentials 'legacy'
    checkAwsCredentials 'target'
    compareTableCounts $@
    ;;
  test)
    INPUT_MOUNT=$(getPwdForGenericSqlMount)
    run $@ files_to_run=inventory.sql log_path=target-counts.log legacy=false ;;
    # compareTableRowCounts source-counts.log target-counts.log ;;
esac