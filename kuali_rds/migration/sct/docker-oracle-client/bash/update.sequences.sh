#!/bin/bash

# DMS ongoing data migration (CDC) does not include changes to sequences, specifically the last sequence advanced to.
# This means that any number of sequences for the target database will drift increasingly behind the sequences of the
# source database as time goes on after the initial migration data load (despite ongoing replication).
# This script updates the sequences in the target database so as to "catch up" with those in the source database.

NEW_SEQUENCES_TABLE='DMS_NEW_SEQUENCES'
OLD_SEQUENCES_TABLE='DMS_OLD_SEQUENCES'
NEW_SEQUENCES_LOG='new_sequences.log'
NEW_SEQUENCES_SQL='new_sequences.sql'
UPDATE_SEQUENCES_SQL='update_sequences.sql'

# Get a space delimited report of all sequences from the source database
#
# EXAMPLE
# sh dbclient.sh update-sequences \
#   SEQUENCE_TASK=report-raw-create \
#   aws_access_key_id=[LEGACY_ACCOUNT_KEY] \
#   aws_secret_access_key=[LEGACY_ACCOUNT_SECRET] \
#   aws_region=us-east-1 \
#   template_bucket_name=kuali-research-ec2-setup \
#   landscape=stg \
#   tunnel=false
getSourceSequencesReport() {
  outputHeading "Creating raw source database sequence report..."
  encoded_sql="$encoded_sql$(echo 'Set pagesize 0
  SET trimspool ON
  SET heading off
  SET echo off
  SET feedback off
  SET verify off
  SET termout off
  SET showmode off
  SET linesize 200
  COLUMN sequence_owner FORMAT A30
  COLUMN sequence_name FORMAT A50
  select sequence_owner, sequence_name, last_number from ALL_SEQUENCES;' | base64 -w 0)"
  run $@ encoded_sql="$encoded_sql" "log_path=$NEW_SEQUENCES_LOG"
}

# Based on the space delimited sequence report, generate an sql file that, when run, will load this report into a table.
# This table will be used later in an inner join to the ALL_SEQUENCES view of the target database to determine what sequences have changed.
#
# EXAMPLE
# sh dbclient.sh update-sequences SEQUENCE_TASK=report-sql-create \
createUploadSqlScript() {
  outputHeading "Creating sql to load sequence report to target database..."
  cat <<EOF > input/$NEW_SEQUENCES_SQL

$(
  for table in $OLD_SEQUENCES_TABLE $NEW_SEQUENCES_TABLE ; do
    cat <<EOF2
      prompt creating table $table...
      declare
      begin
        execute immediate 'CREATE TABLE $table (
          SEQUENCE_OWNER VARCHAR2(128 BYTE) NOT NULL ENABLE, 
          SEQUENCE_NAME VARCHAR2(128 BYTE) NOT NULL ENABLE, 
          LAST_NUMBER NUMBER NOT NULL ENABLE, 
          "TIMESTAMP" TIMESTAMP (6) DEFAULT CURRENT_TIMESTAMP
        )';
      exception when others then
        if SQLCODE = -955 then null; else raise; end if;
      end;
      /
      prompt truncating $table...;
      TRUNCATE TABLE $table;
      /

EOF2
  done
)

prompt inserting current sequences data into $OLD_SEQUENCES_TABLE ...
insert into $OLD_SEQUENCES_TABLE select s.sequence_owner, s.sequence_name, s.last_number, CURRENT_TIMESTAMP from dba_sequences s;
/

$(awk '{print "prompt inserting "$1", "$2", "$3"...;\nINSERT INTO '$NEW_SEQUENCES_TABLE' VALUES(\x27"$1"\x27, \x27"$2"\x27, "$3", CURRENT_TIMESTAMP);\n/"}' \
  output/$NEW_SEQUENCES_LOG)
EOF

  if [ "$DRYRUN" == 'true' ] ; then
    head -50 input/$NEW_SEQUENCES_SQL && printf "\nMore..."
  else
    cat input/$NEW_SEQUENCES_SQL
  fi
}

# Run the script created by createUploadSqlScript() against the target database
#
# EXAMPLE
# sh dbclient.sh update-sequences \
#   SEQUENCE_TASK=report-sql-upload \
#   aws_access_key_id=[TARGET_ACCOUNT_KEY] \
#   aws_secret_access_key=[TARGET_ACCOUNT_SECRET] \
#   aws_region=us-east-1 \
#   landscape=stg \
#   tunnel=false 
runUploadSqlScript() {
  outputHeading "Running sql to load sequence report to target database..."
  run $@ files_to_run=$NEW_SEQUENCES_SQL
}


# Get a space delimited report of all sequences from the source database
#
# EXAMPLE
# sh dbclient.sh update-sequences \
#   SEQUENCE_TASK=resequence \
#   aws_access_key_id=[TARGET_ACCOUNT_KEY] \
#   aws_secret_access_key=[TARGET_ACCOUNT_SECRET] \
#   aws_region=us-east-1 \
#   landscape=stg \
#   tunnel=false
updateSequences() {

  outputHeading "Advancing sequences in target db to match those in source db..."
  
  cat <<EOF > input/$UPDATE_SEQUENCES_SQL
    CREATE OR REPLACE PROCEDURE DMS_UPDATE_SEQUENCES
    IS
    BEGIN
      DECLARE
        v_sql varchar2(200);
        v_count number;
      BEGIN
        v_count := 0;
        dbms_output.put_line('Start updating sequences...');
        FOR v_row IN (
          SELECT O.SEQUENCE_OWNER, O.SEQUENCE_NAME, O.LAST_NUMBER as OLD_NUMBER, N.LAST_NUMBER as NEW_NUMBER 
          FROM $OLD_SEQUENCES_TABLE O, $NEW_SEQUENCES_TABLE N
          WHERE O.SEQUENCE_NAME(+) = N.SEQUENCE_NAME
          AND O.SEQUENCE_OWNER(+) = N.SEQUENCE_OWNER
          AND O.LAST_NUMBER < N.LAST_NUMBER
          AND UPPER(O.SEQUENCE_OWNER) = 'KCOEUS')
        LOOP
          v_count := v_count + 1;
          v_sql := 'alter sequence ' 
            || v_row.sequence_owner 
            || '.' 
            || v_row.sequence_name 
            || ' restart start with ' 
            || v_row.new_number ;
          dbms_output.put_line(v_sql);
          execute immediate v_sql ;
        END LOOP;
        dbms_output.put_line('Updated ' || v_count || ' sequences');
      END;
    END DMS_UPDATE_SEQUENCES;
    /

    set serveroutput on

    DECLARE
        v_user varchar(20);
    BEGIN
        select USER into v_user from dual;
        DBMS_OUTPUT.PUT_LINE('granting alter any sequence to ' || v_user || '...');
        execute immediate 'grant alter any sequence to ' || v_user;
    END;
    /

    execute DMS_UPDATE_SEQUENCES;
    /
EOF

  cat input/$UPDATE_SEQUENCES_SQL
  run $@ files_to_run=$UPDATE_SEQUENCES_SQL
}

[ "$DEBUG" == 'true' ] && set -x

echo " "
echo "---- Parameters for sequence task:"
parseArgs silent=false $@

case "${SEQUENCE_TASK,,}" in
  report-raw-create)
    # If "db_" parms are ommitted, they will be looked up dynamically.
    getSourceSequencesReport $@ \
      "legacy=true" \
      "db_host=$LEGACY_DB_HOST" \
      "db_user=$LEGACY_DB_USER" \
      "db_port=$LEGACY_DB_PORT" \
      "db_sid=$LEGACY_DB_SID" \
      "db_password=$LEGACY_DB_PASSWORD"
    ;;
  report-sql-create)
    createUploadSqlScript $@
    ;;
  report-sql-upload)
    # If "db_" parms are ommitted, they will be looked up dynamically.
    runUploadSqlScript $@ \
      "legacy=false" \
      "db_host=$TARGET_DB_HOST" \
      "db_user=$TARGET_DB_USER" \
      "db_port=$TARGET_DB_PORT" \
      "db_sid=$TARGET_DB_SID" \
      "db_password=$TARGET_DB_PASSWORD"
    ;;
  resequence)
    # If "db_" parms are ommitted, they will be looked up dynamically.
    updateSequences $@ \
      "legacy=false" \
      "db_host=$TARGET_DB_HOST" \
      "db_user=$TARGET_DB_USER" \
      "db_port=$TARGET_DB_PORT" \
      "db_sid=$TARGET_DB_SID" \
      "db_password=$TARGET_DB_PASSWORD"
    ;;
  *)
    echo "SEQUENCE_TASK parameter is missing!"
    ;;
esac
  
