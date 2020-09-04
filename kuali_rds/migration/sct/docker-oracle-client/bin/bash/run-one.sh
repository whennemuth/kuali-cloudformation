#!/bin/bash

# Run a script and exit

[ -z "$FILE_TO_RUN" ] && "ERROR! FILE_TO_RUN parameter is empty." && exit 1
[ ! -f "$FILE_TO_RUN" ] && [ "${FILE_TO_RUN:0:11}" != '/tmp/input/' ] && FILE_TO_RUN=/tmp/input/$FILE_TO_RUN
[ ! -f "$FILE_TO_RUN" ] && echo "ERROR! No such file \"$FILE_TO_RUN\"" && exit 1

FILE_TO_RUN_NAME="$(echo "$FILE_TO_RUN" | awk 'BEGIN{RS="/"}{print $1}' | tail -1)"
[ -z "$LOG_PATH" ] && LOG_PATH="/tmp/output/$FILE_TO_RUN_NAME-$(date '+%s').log"
[ "${LOG_PATH:0:12}" != '/tmp/output/' ] && LOG_PATH=/tmp/output/$LOG_PATH

echo "Processing $FILE_TO_RUN > $LOG_PATH..."

sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE;
  SET FEEDBACK OFF
  spool $LOG_PATH
  @$FILE_TO_RUN
  spool off;
  exit;
EOF
