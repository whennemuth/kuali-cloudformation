#!/bin/bash

source common-functions.sh

parseArgs default_profile=true $@

# Lookups will only work if AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, & LANDSCAPE are set.

canLookupInS3() {
  local reqs=0
  [ -n "$AWS_ACCESS_KEY_ID" ] && ((reqs++))
  [ -n "$AWS_SECRET_ACCESS_KEY" ] && ((reqs++))
  [ -n "$AWS_REGION" ] && ((reqs++))
  [ -n "$LANDSCAPE" ] && ((reqs++))
  [ -n "$BUCKET_NAME" ] && ((reqs++))
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

if [ "$LEGACY" == 'true' ] ; then
  # Database connection should be direct to host, accessible over bu vpn.

  if ! dbParmsComplete && canLookupInS3 ; then
    # Get database details from kc-config.xml in s3
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

  [ -z "$DB_PASSWORD" ] && echo "ERROR! DB password not provided and lookup failed." && exit 1
  [ -z "$DB_HOST" ] && echo "ERROR! DB Host not provided and lookup failed." && exit 1
  [ -z "$DB_USER" ] && DB_USER="KCOEUS"
  [ -z "$LOCAL_PORT" ] && LOCAL_PORT="1521"
else
  # Database connection should be through localhost tunneled to target db endpoint.
  tunnelCmd="sh tunnel.sh silent=true user_terminated=false default_profile=true $@"
  if [ "$DEBUG" == 'true' ] ; then
    echo "$tunnelCmd"
  else
    eval "$tunnelCmd" 2> tunnel.err
    [ -f tunnel.err ] && [ -n "$(cat tunnel.err 2> /dev/null)" ] && cat tunnel.err
    printf "\nTunnel established.\n"
  fi
  [ -z "$DB_PASSWORD" ] && DB_PASSWORD="$(getRdsPassword)"
  [ -z "$DB_PASSWORD" ] && echo "ERROR! DB password not provided and lookup failed." && exit 1
  [ -z "$DB_USER" ] && DB_USER="admin"
  [ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"
  [ -z "$LOCAL_PORT" ] && LOCAL_PORT="5432"
fi

[ -z "$SID" ] && SID="Kuali"

url='
  (DESCRIPTION=(
    ADDRESS_LIST=(FAILOVER=OFF)(LOAD_BALANCE=OFF)(ADDRESS=(PROTOCOL=TCP)
    (HOST='$DB_HOST')(PORT='$LOCAL_PORT')
  ))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME='$SID')))'

if [ "$DEBUG" == 'true' ] ; then
  echo "sqlplus $DB_USER/$DB_PASSWORD@\"$url\""
  exit 0
fi

if [ "$PROCESS_INPUT_DIR" == 'true' ] ; then
  echo "RESUME NEXT"
elif [ -f "$SCRIPT" ] ; then
  # Run a script and exit
  [ -z "$LOG_NAME" ] && LOG_NAME="/tmp/output/$(date '+%b-%d-%Y.%k.%M.%S-output.log')"
  echo "LOG_NAME = $LOG_NAME"
  sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
    WHENEVER SQLERROR EXIT SQL.SQLCODE;
    SET FEEDBACK OFF
    spool $LOG_NAME
    @$SCRIPT
    spool off;
    exit;
EOF
  echo "Return code: $?"
  echo ""
else
  # Interactive session
  sqlplus $DB_USER/$DB_PASSWORD@"$url"
fi
