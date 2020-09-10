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

# There should exist two log files, each containing lines that separate, with a colon, the name of a table and the number of row in that table.
# This function will display any tables that the two files do not have in common, and any matching tables whose row counts differ.
compareTableRowCounts() {
  local source="output/$1"
  [ ! -f "$source" ] && [ "${source:0:7}" != '/output' ] && source="output/$source"
  [ ! -f $source ] && echo "ERROR! No such source file: $source" && exit 1
  
  local target="output/$2"
  [ ! -f "$target" ] && [ "${target:0:7}" != '/output' ] && target="output/$target"
  [ ! -f $target ] && echo "ERROR! No such target file: $target" && exit 1

  declare -A sourceTables=();
  declare -A targetTables=();
  declare -A mismatches=();

  # Display mismatches found thus far
  displayMismatches() {
    for m in ${!mismatches[@]} ; do
      echo "Mismatch found: $m - ${mismatches[$m]}"
    done
  }

  parseLine() {
    local output="name=$(echo "$1" | awk 'BEGIN{RS=":"}{print $1}' | head -1)"
    echo "$output && rows=$(echo "$1" | awk 'BEGIN{RS=":"}{print $1}' | tail -1)"
  }

  # Load the source tables array
  loadSourceTableLog() {
    local counter=0
    while read table ; do
      ((counter++))
      eval "$(parseLine "$table")"
      clear
      echo "Loading source tables..."
      printf "$counter) $name: $rows"
      if [ -n "$rows" ] ; then
        sourceTables["$name"]=$rows
      fi
    done <<< $(cat $source)
    echo " "
    sourceTableCount=$counter
  }

  # Iterate the target tables, comparing with the corresponding source tables for row counts as you go.
  loadTargetTableLog() {
    local counter=0
    while read table ; do
      ((counter++))
      eval "$(parseLine "$table")"
      clear
      echo "Loading target tables..."
      targetTables[$name]=$rows
      if [ ! ${sourceTables[$name]} ] ; then
        mismatches[$name]="source rows: ?, target rows: $rows"
      else
        local sourceRows=${sourceTables[$name]}
        if [ $rows -ne $sourceRows ] || [ "$rows" != "$sourceRows" ]; then
          mismatches[$name]="source rows: $sourceRows, target rows: $rows"
        # else
        #   mismatches[$name]="source rows: $sourceRows, target rows: $rows"
        fi
      fi
      displayMismatches
      echo "Table $counter: $name"
    done <<< $(cat $target)
    echo " "
    targetTableCount=$counter
  }

  # Iterate over the source tables log again, now that the target tables log has been loaded, 
  # to detect any source tables that don't exist in the target log.
  checkMissingTargetTables() {
    local counter=0
    while read table ; do
      ((counter++))
      eval "$(parseLine "$table")"
      clear
      echo "Finding any missing target tables..."
      if [ ! ${targetTables[$name]} ] ; then
        mismatches[$name]="source rows: $rows, target rows: ?"
      fi
      displayMismatches
      echo "Table $counter: $name"
    done <<< $(cat $source)
  }
  
  displayResults() {
    clear
    echo "RESULTS: source tables: $sourceTableCount, target tables: $targetTableCount"
    for m in ${!mismatches[@]} ; do
      echo "Mismatch found: $m - ${mismatches[$m]}"
    done
  }

  loadSourceTableLog 

  loadTargetTableLog

  checkMissingTargetTables

  displayResults
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
  table-counts)
    run $@ files_to_run=inventory.sql log_path=source-counts.log ;;
  compare-table-counts)
    run $@ legacy=true  files_to_run=inventory.sql log_path=source-counts.log
    run $@ legacy=false files_to_run=inventory.sql log_path=target-counts.log
    compareTableRowCounts source-counts.log target-counts.log ;;
  test)
    compareTableRowCounts source-counts.log target-counts.log ;;
esac