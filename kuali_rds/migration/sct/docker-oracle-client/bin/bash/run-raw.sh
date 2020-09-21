#!/bin/bash

# Run a script and exit

[ -z "$ENCODED_SQL" ] && "ERROR! ENCODED_SQL parameter is empty." && exit 1
RAW_SQL="$(echo "$ENCODED_SQL" | base64 -d)"

[ -z "$LOG_PATH" ] && LOG_PATH="/tmp/output/raw-sql-$(date '+%s').log"
[ "${LOG_PATH:0:12}" != '/tmp/output/' ] && LOG_PATH=/tmp/output/$LOG_PATH

echo "Processing $RAW_SQL > $LOG_PATH..."

sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE;
  -- SET FEEDBACK OFF
  spool $LOG_PATH
  $RAW_SQL
  spool off;
  exit;
EOF
