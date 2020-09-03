#!/bin/bash

declare -A defaults=(
  [PROFILE]='infnprd'
  [LANDSCAPE]='sb'
  [RDS_REGION]='us-east-1'
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

# The schema conversion tool does not properly grant access on the kuali attachments directory.
modifyDirectoryGrant() {
  local sqlfile="$1"
  echo "Correcting any bad directory grants in $sqlfile..."
  sed -i 's/SYS.KUALI_ATTACHMENTS/DIRECTORY KUALI_ATTACHMENTS/g' $sqlfile
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

# The oracle client is run in a docker container. If the image for that container does not exist,
# load or build it here.
checkOracleClient() {
  if [ -z "$(docker images -q oracle/oracleclient)" ] ; then
    if [ -f oracleclient.tar.gz ] ; then
      docker load < oracleclient.tar.gz
    elif [ -f docker-oracle-client/oracleclient.tar.gz ] ; then
      docker load < docker-oracle-client/oracleclient.tar.gz
    else
      if [ ! -d docker-oracle-client ] ; then
        git clone https://github.com/grenadejumper/docker-oracle-client.git
      fi
      if [ ! -d docker-oracle-client ] ; then
        echo "Cannot install docker sql client for oracle: https://github.com/grenadejumper/docker-oracle-client.git"
        exit 1
      fi
      cd docker-oracle-client
      docker build -t oracle/oracleclient .
      cd ..
    fi
  fi
  if [ -z "$(docker images -q oracle/oracleclient)" ] ; then
    echo "Cannot install docker image for oracle sql client!"
    exit 1
  fi
}


# The oracle client runs in a docker container. The connection details for the client are supplied
# as environment variables in the docker run command. These variables should exist in a "oracleclient.env" file.
checkOracleClientEnv() {
  if [ ! -f oracleclient.env ] ; then
    echo "You Must create an oracleclient.env file with connection variables for the oracle database (see README.md)"
    exit 1
  else
    source ./oracleclient.sh
    if [ -z "$ORACLE_PASSWORD" ] ; then
      echo "You Must set a password value in the oracleclient.env file!"
      exit 1
    fi
  fi
}


runSqlFile() {

  local sqlfile="${1:-$SQL_FILE}"

  checkOracleClientEnv

  checkOracleClient

  local connectionString='
  $ORACLE_USERNAME/$ORACLE_PASSWORD@
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $ORACLE_HOST)(PORT = $ORACLE_PORT))
      (CONNECT_DATA =
        (SERVER = DEDICATED)
        (SERVICE_NAME = $ORACLE_DATABASE)
      )
    )
  '

  # https://zwbetz.com/connect-to-an-oracle-database-and-run-a-query-from-a-bash-script/
  # The SET PAGESIZE 0 option suppresses all headings, page breaks, titles, the initial blank line, and other formatting information
  # The SET FEEDBACK OFF option suppresses the number of records returned by a script
  # The -S option sets silent mode which suppresses the display of the SQL*Plus banner, prompts, and echoing of commands
  # The -L option indicates a logon, which is to be followed by a connection string.
  if [ -n "$sqlfile" ] ; then
    cat <<-EOF > $cmdfile
    docker run --rm \\
      --env-file oracleclient.env \\
      -p 5432:1521 \\
      -v $sqlfile:/tmp/$sqlfile
      $([ -f 'tnsnames.ora' ] && echo '-v tnsnames.ora:/usr/lib/oracle/12.2/client/network/admin/tnsnames.ora') \\
      oracle/oracleclient \\
      echo -e "SET PAGESIZE 0\n SET FEEDBACK OFF\n $/tmp/$sqlfile" | \\
      sqlplus -S -L '$connectionString'
EOF
  else
    cat <<-EOF > $cmdfile
    docker run --rm \\
      --env-file oracleclient.env \\
      -p 5432:1521 \\
      $([ -f 'tnsnames.ora' ] && echo '-v tnsnames.ora:/usr/lib/oracle/12.2/client/network/admin/tnsnames.ora') \\
      oracle/oracleclient \\
      sqlplus -S -L '$connectionString'
EOF
  fi
}

cleanSqlFile() {

  clean() {
    local type="$1"
    case "$type" in
      user)
        modifyDirectoryGrant "$sqlfile"
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
    esac
  }

  local sqlfile="$1"
  local shortname="$(echo $sqlfile | awk 'BEGIN {RS="/"} {print $1}' | tail -1)"
  case "$shortname" in
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
      clean 'user' ;;
    12.create.user.roles.sql)
      clean 'role' ;;
    13.create.remaining.users.sql)
      clean 'user' ;;
  esac
}


processSql() {
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

  # Run all sql files
  for sql in ${sqlfiles[@]} ; do
    echo "Processing $sql ..."
    case "$task" in
      run-sql)
        runSqlFile $sql ;;
      clean-sql)
        cleanSqlFile $sql ;;
    esac
  done
}


runTask() {
  case "$task" in
    run-sql|clean-sql)
      processSql $@ ;;
    run-sql-file)
      processSql $@;;
    clean-sql-file)
      processSql $@ ;;
    get-password)
      # Must include PROFILE and LANDSCAPE
      getRdsPassword ;;
    test)
      cat sql/ci-example/test.sql > sql/ci-example/test2.sql
      removeDropStatements sql/ci-example/test2.sql ;;
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