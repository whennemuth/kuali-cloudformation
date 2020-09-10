#!/bin/bash

# Remove any windows only characters and blank/whitespace-only lines in transaction block (sqlplus will throw error)
for f in $(ls -1 /tmp/input/*.sql) ; do
  # Remove windows only characters
  dos2unix $f
  # Remove whitespace only lines (sqlplus will throw error if one or more is in transaction block)
  sed -r -i 's/^[\x20\t]+$//g' $f
  # Remove blank lines (sqlplus will throw error if one or more is in transaction block)
  sed -i '/^$/d' $f
  # Restore some blank lines after "/" commit markers (between transaction blocks) to provide separation
  sed -i 's/^\/$/\/\n\n/g' $f
done

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

