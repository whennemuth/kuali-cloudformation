#!/bin/bash

declare -A defaults=(
  [PROFILE]='infnprd'
  [LANDSCAPE]='sb'
  [RDS_REGION]='us-east-1'
  # [BASTION_AVAILABILITY_ZONE]='???'
  # [RDS_ENDPOINT]='???'
  # [BASTION_INSTANCE_ID]='???'
)

convertSqlFiles=(
  '01.tablespace.kualico.create.sql'
  '02.profile.noexpire.create.sql'
  '03.user.kualico.create.sql'
  '04.user.kualico.grant.tablespace.sql'
  '05.schema.kualico.create.sql'
)

run() {
  source ../../../scripts/common-functions.sh

  if ! isCurrentDir 'sct' ; then
    echo "You must run this script from the sct (schema conversion tool) subdirectory!."
    exit 1
  fi

  task="${1,,}"
  shift

  if [ "$task" != "test" ] ; then

    parseArgs $@

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
  sed -i 's/SEGMENT CREATION DEFERRED/SEGMENT CREATION IMMEDIATE/g' $sqlfile
}


convertSchema() {
  sqlfiles=()
  # Collect up all parameters that are not assignments (do not container "=") and that are verified as the 
  # names of existing files. These should be sql files
  for arg in $@ ; do
    if [ -z "$(grep '=' <<< $arg)" ] ; then
      if [ -f "$arg" ] ; then
        sqlfiles=(${sqlfile[@]} $arg)
      fi
    fi
  done

  # If no sql files were provided, assume ALL sql files need to be run
  [ ${#sqlfiles[@]} -eq 0 ] && sqlfiles=${convertSqlFiles[@]}

  # Run all sql files
  for sql in ${sqlfiles[@]} ; do
    echo "Processing $sql ..."
    runSql $sql
  done
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


runSql() {

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


runTask() {
  case "$task" in
    convert-schema)
      convertSchema $@ ;;
    run-sql)
      runSql ;;
    test)
      echo "testing" ;;
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