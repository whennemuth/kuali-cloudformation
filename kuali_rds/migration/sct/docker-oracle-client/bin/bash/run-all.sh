#!/bin/bash

sqlplus -s $DB_USER/$DB_PASSWORD@"$url" <<-EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE;
  SET FEEDBACK OFF
  $(
    i=1
    for f in $(ls -1 /tmp/input/*.sql | grep -o -e '[^/]*$') ; do
      log=$(echo $f | sed 's/\.sql/\.log/')
      printf \\n'    spool /tmp/output/'$log
      printf \\n'    @/tmp/input/'$f
      ((i++))
    done
  )
  spool off;
  exit;
EOF

