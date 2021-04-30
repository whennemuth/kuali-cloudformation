#!/bin/bash

# Run a script and exit

[ -z "$ENCODED_SQL" ] && "ERROR! ENCODED_SQL parameter is empty." && exit 1
[ -z "$LOG_PATH" ] && LOG_PATH="/tmp/output/raw-sql-$(date '+%s').log"
[ "${LOG_PATH:0:12}" != '/tmp/output/' ] && LOG_PATH=/tmp/output/$LOG_PATH

# The provided sql is base64 encoded and can be either one single encoded string or 
# multiple encoded segments separated with a "@" character.
for encodedSegment in $(echo $ENCODED_SQL | awk 'BEGIN{RS="@"}{print $1}') ; do

  [ -z "$encodedSegment" ] && continue;
  raw_sql="$(echo "$encodedSegment" | base64 -d)"
  echo "Processing $raw_sql > $LOG_PATH..."

  if [ "$DRYRUN" != 'true' ] ; then
    sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
      WHENEVER SQLERROR EXIT SQL.SQLCODE;
      -- SET FEEDBACK OFF
      spool $LOG_PATH
      $raw_sql
      spool off;
      exit;
EOF
  else
    cat <<EOF
    sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
      WHENEVER SQLERROR EXIT SQL.SQLCODE;
      -- SET FEEDBACK OFF
      spool $LOG_PATH
      $raw_sql
      spool off;
      exit;
EOF
  fi
done
