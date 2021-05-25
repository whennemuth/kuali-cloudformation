#!/bin/bash

# ------------------------------------------------------------------------------------------------------ #
# This is the entrypoint script for the docker container.
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are always required as parameters for lookups and ssm use.
# ------------------------------------------------------------------------------------------------------ #

source common-functions.sh

canLookupInS3() {
  local reqs=0
  [ -z "$BASELINE" ] && BASELINE="$LANDSCAPE"
  [ -z "$TEMPLATE_BUCKET_NAME" ] && TEMPLATE_BUCKET_NAME="$BUCKET_NAME"
  [ -n "$AWS_ACCESS_KEY_ID" ] && ((reqs++))
  [ -n "$AWS_SECRET_ACCESS_KEY" ] && ((reqs++))
  [ -n "$AWS_REGION" ] && ((reqs++))
  [ -n "$BASELINE" ] && ((reqs++))
  [ -n "$TEMPLATE_BUCKET_NAME" ] && ((reqs++))
  [ $reqs -eq 5 ] && true || false
}

dbParmsComplete() {
  local reqs=0
  [ -n "$DB_HOST" ] && ((reqs++))
  [ -n "$DB_PASSWORD" ] && ((reqs++))
  [ -n "$DB_USER" ] && ((reqs++))
  [ -n "$DB_SID" ] && ((reqs++))
  [ -n "$DB_PORT" ] && ((reqs++))
  [ $reqs -eq 5 ] && true || false
}

setLocalhostDbParms() {
  [ -z "$DB_USER" ] && DB_USER="admin"
  [ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"
  [ -z "$DB_PORT" ] && DB_PORT="5432"
  [ -z "$DB_SID" ] && DB_SID="Kuali"
}

setExplicitDbParms() {
  [ -n "$DB_HOST" ] && DB_HOST="$DB_HOST"
  [ -n "$DB_PASSWORD" ] && DB_PASSWORD="$DB_PASSWORD"
  [ -n "$DB_USER" ] && DB_USER="$DB_USER"
  [ -n "$DB_SID" ] && DB_SID="$DB_SID"
  [ -n "$DB_PORT" ] && DB_PORT="$DB_PORT"
  [ -z "$DB_SID" ] && DB_SID="Kuali"
  [ -z "$DB_PORT" ] && DB_PORT="1521"
}

printDbParms() {
  echo "DB_HOST=$DB_HOST"
  echo "DB_SID=$DB_SID"
  echo "DB_PORT=$DB_PORT"
  echo "DB_USER=$DB_USER"
  echo "DB_PASSWORD="$(maskString "${DB_PASSWORD}")""
}

setLegacyParms() {
  # Database connection should be direct to host, accessible over bu vpn.

  setExplicitDbParms

  if ! dbParmsComplete && canLookupInS3 ; then
    # Get database details from kc-config.xml in s3
    echo "Performing s3 lookup for kc-config.xml..."
    counter=1
    while read dbParm ; do
      case $counter in
        1) [ -z "$DB_PASSWORD" ] && DB_PASSWORD="$dbParm" ;;
        2) [ -z "$DB_HOST" ] && DB_HOST="$dbParm" ;;
        3) [ -z "$DB_SID" ] && DB_SID="$dbParm" ;;
        4) [ -z "$DB_PORT" ] && DB_PORT="$dbParm" ;;
        5) [ -z "$DB_USER" ] && DB_USER="$dbParm" ;;
      esac
      ((counter++))
    done <<< $(getKcConfigDb)
  fi
  local status
  [ -z "$DB_PASSWORD" ] && printf "ERROR! Legacy DB password not provided and lookup %s.\n" \
    "$(canLookupInS3 && printf 'failed' || printf 'needs more parameters from you to work')" && exit 1
  [ -z "$DB_HOST" ] && printf "ERROR! Legacy DB Host not provided and lookup %s.\n" \
    "$(canLookupInS3 && printf 'failed' || printf 'needs more parameters from you to work')" && exit 1
  [ -z "$DB_USER" ] && DB_USER="KCOEUS"
  [ -z "$DB_PORT" ] && DB_PORT="1521"

  printDbParms
}


setRdsParms() {  

  setExplicitDbParms

  if [ -z "$DB_PASSWORD" ] ; then
    landscape="$BASELINE"
    [ -z "$landscape" ] && landscape="$LANDSCAPE"
    DB_PASSWORD="$(getDbPassword 'admin' "$landscape")"
  fi

  [ -z "$DB_PASSWORD" ] && echo "ERROR! RDS DB password not provided and lookup failed." && exit 1

  if [ "${TUNNEL,,}" == 'true' ] ; then
    local tunnel='true'
  elif isUnknownHost ; then
    echo "Looking up rds instance for host and port values..."
    local json=$(getRdsJson $landscape)
    DB_HOST=$(echo "$json" | jq .Endpoint.Address)
    DB_PORT=$(echo "$json" | jq .Endpoint.Port)
  fi

  if isLocalHost || isUnknownHost ; then
    local tunnel='true'
    echo "WARNING! The \"TUNNEL\" parameter was not set to true, but no database HOST can be determined."
    echo "Will attempt to establish tunnel anyway..."
  fi

  [ -z "$DB_USER" ] && DB_USER="admin"
  [ -z "$DB_SID" ] && DB_SID="Kuali"

  printDbParms

  if [ "$tunnel" == 'true' ] ; then
    setLocalhostDbParms
    startTunnel $@
  fi
}

isRemoteHost() {
  ( [ -n "$DB_HOST" ] && ! isLocalHost ) && true || false
}
isLocalHost() {
  ( [ "$DB_HOST" == '127.0.0.1' ] || [ "$DB_HOST" == 'localhost' ] ) && true || false
}
isUnknownHost() {
  [ -z "$DB_HOST" ] && true || false
}

# Database connection should be through localhost tunneled to target db endpoint, unless
# specific details are provided that indicate the db host can be reached directly.
startTunnel() {
  tunnelCmd="sh tunnel.sh silent=true user_terminated=false default_profile=true $@"
  if [ "$DEBUG" == 'true' ] ; then
    echo "$tunnelCmd"
  else
    local errfile=/tmp/output/tunnel.err
    eval "$tunnelCmd" 2>> $errfile
    local errcode=$?
    if [ -f $errfile ] ; then
      cat $errfile
    fi
    if [ $errcode -ge 101 ] && [ $errcode -le 106 ] ; then
      printf "\nTunnel failed. Exiting."
      exit $errcode
    fi
    printf "\nTunnel established.\n"
  fi
}


setConnectionParms() {
  if [ "$LEGACY" == 'true' ] ; then
    setLegacyParms $@
  else
    setRdsParms $@
  fi
  [ -z "$DB_SID" ] && DB_SID="Kuali"
}


setConnectionURL() {
  url='
    (DESCRIPTION=(
      ADDRESS_LIST=(FAILOVER=OFF)(LOAD_BALANCE=OFF)(ADDRESS=(PROTOCOL=TCP)
      (HOST='$DB_HOST')(PORT='$DB_PORT')
    ))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME='$DB_SID')))'

  if [ "$DEBUG" == 'true' ] ; then
    echo "sqlplus $DB_USER/$DB_PASSWORD@\"$url\""
    exit 0
  fi
}


connectAndRun() {
  if [ "$FILES_TO_RUN" == 'all' ] ; then
    sh run-all.sh
  elif [ -n "$FILES_TO_RUN" ] ; then
    # One or more .sql scripts have been provided as a comma-delimited list of file names.
    for f in $(echo $FILES_TO_RUN | sed 's/,/ /g') ; do
      if [ -n "$(echo $f | grep '.*\.sql')" ] ; then
        FILE_TO_RUN=$f
        sh run-one.sh
      fi
    done
  elif [ -n "$ENCODED_SQL" ] ; then
    sh run-raw.sh
  else
    sqlplus $DB_USER/$DB_PASSWORD@"$url"
  fi
}

set -a 

parseArgs default_profile=true $@

setConnectionParms $@

setConnectionURL

connectAndRun

