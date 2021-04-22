#!/bin/bash

# ------------------------------------------------------------------------------------------------------ #
# This is the entrypoint script for the docker container.
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are always required as parameters for lookups and ssm use.
# ------------------------------------------------------------------------------------------------------ #

source common-functions.sh

canLookupInS3() {
  local reqs=0
  [ -n "$AWS_ACCESS_KEY_ID" ] && ((reqs++))
  [ -n "$AWS_SECRET_ACCESS_KEY" ] && ((reqs++))
  [ -n "$AWS_REGION" ] && ((reqs++))
  [ -n "$LANDSCAPE" ] && ((reqs++))
  [ -n "$TEMPLATE_BUCKET_NAME" ] && ((reqs++))
  [ $reqs -eq 5 ] && true || false
}

dbParmsComplete() {
  local reqs=0
  [ -n "$DB_HOST" ] && ((reqs++))
  [ -n "$DB_PASSWORD" ] && ((reqs++))
  [ -n "$DB_USER" ] && ((reqs++))
  [ -n "$SID" ] && ((reqs++))
  [ -n "$LOCAL_PORT" ] && ((reqs++))
  [ $reqs -eq 5 ] && true || false
}

setLegacyParms() {
  # Database connection should be direct to host, accessible over bu vpn.
  if ! dbParmsComplete && canLookupInS3 ; then
    # Get database details from kc-config.xml in s3
    echo "Performing s3 lookup for kc-config.xml..."
    counter=1
    while read dbParm ; do
      case $counter in
        1) [ -z "$DB_PASSWORD" ] && DB_PASSWORD="$dbParm" ;;
        2) [ -z "$DB_HOST" ] && DB_HOST="$dbParm" ;;
        3) [ -z "$SID" ] && SID="$dbParm" ;;
        4) [ -z "$LOCAL_PORT" ] && LOCAL_PORT="$dbParm" ;;
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
  [ -z "$LOCAL_PORT" ] && LOCAL_PORT="1521"
}


setRdsParms() {  
  if needTunnel ; then
    startTunnel $@
  fi

  if [ -z "$DB_PASSWORD" ] ; then
    landscape="$BASELINE"
    [ -z "$landscape" ] && landscape="$LANDSCAPE"
    getDbPassword 'admin' "$landscape"
    DB_PASSWORD="$(getDbPassword 'admin' "$landscape")"
  fi
  [ -z "$DB_PASSWORD" ] && echo "ERROR! RDS DB password not provided and lookup failed." && exit 1
  [ -z "$DB_USER" ] && DB_USER="admin"
  [ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"
  [ -z "$LOCAL_PORT" ] && LOCAL_PORT="5432"
}


# A tunnel is needed if the TUNNEL parameter is true, or the DB_HOST parameter is unset or indicates localhost.
needTunnel() {
  local need='false'
  [ "${TUNNEL,,}" == 'true' ] && need='true'
  [ -z "$DB_HOST" ] && need='true'
  [ "$DB_HOST" == '127.0.0.1' ] && need='true'
  [ "$DB_HOST" == 'localhost' ] && need='true'
  [ $need == 'true' ] && true || false
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
  [ -z "$SID" ] && SID="Kuali"
}


setConnectionURL() {
  url='
    (DESCRIPTION=(
      ADDRESS_LIST=(FAILOVER=OFF)(LOAD_BALANCE=OFF)(ADDRESS=(PROTOCOL=TCP)
      (HOST='$DB_HOST')(PORT='$LOCAL_PORT')
    ))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME='$SID')))'

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
        # if [ "$DRYRUN" == 'true' ] ; then
        #   echo "DRYRUN: $f"
        # else
          sh run-one.sh
        # fi
      fi
    done
  elif [ -n "$ENCODED_SQL" ] ; then
    # if [ "$DRYRUN" == 'true' ] ; then
    #   echo "DRYRUN: $ENCODED_SQL"
    # else
      sh run-raw.sh
    # fi
  else
    sqlplus $DB_USER/$DB_PASSWORD@"$url"
  fi
}

set -a 

parseArgs default_profile=true $@

setConnectionParms $@

setConnectionURL

connectAndRun

