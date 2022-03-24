#!/bin/bash

# Remove any windows only characters and blank/whitespace-only lines in transaction block (sqlplus will throw error)
if [ "$DRYRUN" != 'true' ] ; then
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
fi

if [ "$DRYRUN" != 'true' ] ; then
  sqlplus -s $DB_USER/$DB_PASSWORD@"$sqlplusUrl" <<-EOF
    WHENEVER SQLERROR EXIT SQL.SQLCODE;
    SET FEEDBACK OFF
    $(
      i=1
      for f in $(ls -1 /tmp/input/*.sql | grep -o -e '[^/]*$') ; do
        log=$(echo $f | sed 's/\.sql/\.log/')
        printf \\n'    prompt beginning script '$f'...'
        printf \\n'    spool /tmp/output/'$log
        printf \\n'    @/tmp/input/'$f
        ((i++))
      done
    )
    spool off;
    exit;
EOF
else 
  cat <<EOF
  sqlplus -s $DB_USER/$DB_PASSWORD@"$sqlplusUrl" <<-EOF
    WHENEVER SQLERROR EXIT SQL.SQLCODE;
    SET FEEDBACK OFF
    $(
      for f in $(ls -1 /tmp/input/*.sql | grep -o -e '[^/]*$') ; do
        printf \\n'    prompt DRYRUN: script '$f'...'
      done
    )
    exit;
EOF
fi
