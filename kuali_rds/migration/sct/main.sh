#!/bin/bash

declare -A defaults=(
  [LANDSCAPE]='sb'
  [RDS_REGION]='us-east-1'
  # [PROFILE]='???'
  # [BASTION_AVAILABILITY_ZONE]='???'
  # [RDS_ENDPOINT]='???'
  # [BASTION_INSTANCE_ID]='???'
)


run() {
  source ../../../scripts/common-functions.sh

  if ! isCurrentDir 'sct' ; then
    echo "You must run this script from the sct (schema conversion tool) subdirectory!"
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] ; then

    [ -z "$PROFILE" ] && PROFILE='default'

    parseArgs silent=true $@

    setDefaults
  fi

  runTask $@
}


condenseEmptyLines() {
  lines={$1:-1}
  for sql in $(ls -1 *.sql) ; do
    cat $sql | awk '!NF {if (++n <= 1) print; next}; {n=0;print}' > sql.temp && cat sql.temp > $sql
  done
  [ -f sql.temp ] && rm sql.temp
}


# Segment creation on demand, or deferred segment creation as it is also known, 
# is a space saving feature of Oracle Database 11g Release 2. When non-partitioned tables are created, 
# none of the associated segments (table, implicit index and LOB segments) are created until rows are 
# inserted into the table. For systems with lots of empty tables, this can represent a large space saving.
# Only available with oracle-ee engine.
removeDeferredSegments() {
  local sqlfile="$1"
  echo "Removing any deferred segments in $sqlfile..."
  sed -i 's/SEGMENT CREATION DEFERRED/SEGMENT CREATION IMMEDIATE/g' $sqlfile
}

# The schema conversion tool outputs sql that grants access on the kuali attachments directory.
# This directory is not being created up at the RDS counterpart database, so this grant must be removed.
# NOTE: S3 attachments for kuali will be enabled instead, removing the db server directory-based approach altogether.
removeDirectoryGrant() {
  local sqlfile="$1"
  echo "Correcting any bad directory grants in $sqlfile..."
  local linenum=$(grep -n '^.*KUALI_ATTACHMENTS.*$' $sqlfile | cut -d':' -f1 2> /dev/null)
  [ -z "$linenum" ] && echo "None found." && return 0
  # Delete the line and the one following it (has the commit "/")
  sed -i "${linenum}d" $sqlfile
  sed -i "${linenum}d" $sqlfile
}

removeCompression() {
  local sqlfile="$1"
  echo "Removing any compress occurrences in $sqlfile..."
  # Obfuscate "NOCOMPRESS" so its "COMPRESS" portion can no longer be matched.
  sed -i 's/NOCOMPRESS/NO#OMPRESS/g' $sqlfile
  # Change any remaining "COMPRESS" occurrences to "NOCOMPRESS"
  sed -i 's/COMPRESS/NOCOMPRESS/g' $sqlfile
  # Restore all prior "NOCOMPRESS" occurrences.
  sed -i 's/NO#OMPRESS/NOCOMPRESS/g' $sqlfile
}

fixMissingQuotes() {
  local sqlfile="$1"
  echo "Fixing any missing quotes in $sqlfile..."
  while read line ; do
    [ -z "$line" ] && continue;
    # Isolate the line number
    local lineNo=$(echo "$line" | grep -Po '^\d+')
    # Now that we have the line number, trim it off the line.
    line=${line:(($(expr length $lineNo)+1))}
    # Print out the old line and its correction
    echo "Modifying line $lineNo:"
    echo "   $line"
    echo "Correction to line:"
    local corrected=$(echo $line \
      | sed 's/,[[:space:]]/", "/g' \
      | sed 's/(/("/g' \
      | sed 's/)/")/g'
    )
    echo "   $corrected"
    # Apply the correction
    sed -i "${lineNo}s/.*/$corrected/" $sqlfile
  done <<< $(grep -n -P 'CREATE OR REPLACE FORCE VIEW[^\(]*\(.*\w\x20\w' $sqlfile)
}

removeRecycleBinGrants() {
  local sqlfile="$1"
  echo "Removing any recycle bin grants in $sqlfile..."
  sed -i 's/.*\.BIN\$.*//g' $sqlfile
}

# Remove all the drop statements from the specified SQL file.
# Assumes that these statements all occur at the top of the file and all lines above and including the last occurrence can be removed.
removeDropStatements() {
  local sqlfile="$1"
  echo "Removing DROP statements from $sqlfile..."
  local lastLine=""
  while read line ; do
    # Isolate the line number
    local lineNo=$(echo "$line" | grep -Po '^\d+')
    # Now that we have the line number, trim it off the line.
    line=${line:(($(expr length $lineNo)+1))}  
    local statementLen=$(expr length "$line")
    [[ ( -n "$(echo $line | grep -i 'DROP ')"  ||  $statementLen -le 1 ) ]] && lastLine=$lineNo
  done <<< $(grep -n -P -B1 -A5 'DROP (FUNCTION|SEQUENCE|TABLE|PROCEDURE|CONSTRAINT|VIEW)\s+' $sqlfile | tail -6)
  tail --lines=+$lastLine $sqlfile > ${sqlfile}.temp
  cat ${sqlfile}.temp > $sqlfile
  rm -f ${sqlfile}.temp
}

autoExtendTableSpaces() {
  sed -r -i 's/CREATE\s+TABLESPACE\s+KUALI_DATA/CREATE BIGFILE TABLESPACE KUALI_DATA/I' $1
  cat <<EOF >> $1

ALTER TABLESPACE KUALI_DATA AUTOEXTEND ON MAXSIZE UNLIMITED;
/

ALTER TABLESPACE SYSTEM AUTOEXTEND ON MAXSIZE UNLIMITED;
/

-- AUTOEXTENSIBLE should be "YES" now. Check with this query:
-- select TABLESPACE_NAME, FILE_NAME,AUTOEXTENSIBLE,MAXBYTES from dba_Data_files where TABLESPACE_NAME = 'KUALI_DATA';
EOF
}

cleanSqlFile() {

  clean() {
    local type="$1"
    case "$type" in
      user)
        removeDirectoryGrant "$sqlfile"
        removeRecycleBinGrants "$sqlfile"
        ;;
      role)
        removeRecycleBinGrants "$sqlfile"
        ;;
      schema)
        removeDropStatements "$sqlfile"
        removeCompression "$sqlfile"
        removeDeferredSegments "$sqlfile"
        removeRecycleBinGrants "$sqlfile"
        fixMissingQuotes "$sqlfile"
        ;;
      tablespace)
        autoExtendTableSpaces "$sqlfile"
        ;;
    esac
  }

  local sqlfile="$1"
  local shortname="$(echo $sqlfile | awk 'BEGIN {RS="/"} {print $1}' | tail -1)"
  case "$shortname" in
    01.create.tablespaces.sql)
      clean 'tablespace' ;;
    03.create.kcoeus.user.sql)
      clean 'user' ;;
    05.create.kcoeus.schema.sql)
      clean 'schema' ;;
    06.create.4.users.sql)
      clean 'user' ;;
    08.create.4.schemas.sql)
      clean 'schema' ;;
    09.create.kcrmproc.user.sql)
      clean 'user' ;;
    11.create.kcrmproc.schema.sql)
      clean 'schema' ;;
    12.create.user.roles.sql)
      clean 'role' ;;
    13.create.remaining.users.sql)
      clean 'user' ;;
  esac
}


cleanSqlFiles() {
  sqlfiles=()
  # Collect up all parameters that are not assignments (do not contain "=") and that are verified as the 
  # names of existing files. These should be sql files
  for arg in $@ ; do
    if [ -z "$(grep '=' <<< $arg)" ] ; then
      if [ -f "$arg" ] ; then
        sqlfiles=(${sqlfiles[@]} $arg)
      fi
    fi
  done

  # If no sql files were provided, assume ALL sql files need to be run
  [ ${#sqlfiles[@]} -eq 0 ] && sqlfiles=$(find sql/$LANDSCAPE -type f -iname *.sql)

  # Clean all sql files
  for sql in ${sqlfiles[@]} ; do
    echo "Cleaning $sql ..."
    cleanSqlFile $sql
  done
}


runTask() {
  case "$task" in
    clean-sql)
      cleanSqlFiles $@ ;;
    get-password)
      # Must include PROFILE and LANDSCAPE
      getRdsAdminPassword ;;
    test)
      autoExtendTableSpaces sql/ci-example/01.create.tablespaces.sql ;;
    *)
      if [ -n "$task" ] ; then
        echo "INVALID PARAMETER: No such task: $task"
      else
        echo "MISSING PARAMETER: task"
      fi
      exit 1
      ;;
  esac
}

run $@