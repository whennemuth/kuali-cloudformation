-- Quick script to disable all foreign keys listed in the DMS_FK_PERMANENTLY_DISABLED table in case they somehow got enabled.
DECLARE
    v_sql varchar2(200);
    v_count number;
BEGIN
    v_count := 0;
    dbms_output.put_line('Start disabling foreign keys...');
    FOR v_row IN (select * from DMS_FK_PERMANENTLY_DISABLED)
    LOOP
        begin
            v_sql := 'alter table KCOEUS.'
                || v_row.table_name
                || ' disable constraint '
                || v_row.constraint_name;
            dbms_output.put_line(v_sql);
            execute immediate v_sql;
            commit;
            v_count := v_count + 1;
        exception
            when others then
                if sqlcode=-2431 then
                    dbms_output.put_line('No such constraint: ' || v_row.constraint_name);
                    rollback;
                else
                    dbms_output.put_line(sqlcode);
                    dbms_output.put_line('Exiting...');
                    rollback;
                    return;
                end if;
        end;
    END LOOP;
    dbms_output.put_line('Disabled ' || v_count || ' foreign keys');
END;
commit;


