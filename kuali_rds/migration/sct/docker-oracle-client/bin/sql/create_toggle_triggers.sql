-- set serveroutput on;
create or replace procedure populate_trigger_toggle_table (
    schema_name in varchar2
) 
authid current_user is
begin
    declare 
        v_count number;
        v_sql varchar2(200);
    begin        
        -- Baseline select for getting a schemas triggers
        v_sql := 'select owner, trigger_name ' ||
            'from sys.all_triggers ' ||
            'where owner = ''' || schema_name || ''' ' ||
            'and status = ''ENABLED''';

        -- Determine if trigger exists (dms_trigger is used to log which triggers will be or have been disabled)
        select count(*) into v_count from dba_tables where table_name = 'DMS_TRIGGER' and owner = 'ADMIN';
        if v_count=0 then
            DBMS_OUTPUT.PUT_LINE('create table dms_trigger as ' || v_sql);
            execute immediate 'create table dms_trigger as ' || v_sql;
        else
            execute immediate 'select count(*) from dms_trigger where owner = ''' || schema_name || '''' into v_count;
            if v_count=0 then
                -- dms_trigger already exists but has no entries for the specified schemas triggers, so insert them.
                execute immediate 'insert into dms_trigger ' || v_sql;
            end if;
        end if;
    end;
end populate_trigger_toggle_table;
/


execute populate_trigger_toggle_table('KCOEUS')
/
execute populate_trigger_toggle_table('KCRMPROC')
/
execute populate_trigger_toggle_table('KULUSERMAINT')
/
execute populate_trigger_toggle_table('SAPBWKCRM')
/
execute populate_trigger_toggle_table('SAPETLKCRM')
/
execute populate_trigger_toggle_table('SNAPLOGIC')
/


create or replace procedure toggle_triggers (
    schema_name in varchar2,
    task in varchar2
) 
authid current_user is
begin        
    declare
        v_sql varchar2(200);
        type trig_typ is table of dms_trigger%ROWTYPE index by pls_integer;
        toggled_triggers trig_typ;
        err_msg varchar2(100);
    begin
        -- Validate the task entry
        if (upper(task)!='ENABLE' and upper(task)!='DISABLE') then
            raise_application_error(-20001, 'Invalid task parameter! expecting ''DISABLE'' or ''ENABLE''');
        end if;
        
        populate_trigger_toggle_table(schema_name);
        
        execute immediate 'select * from dms_trigger where owner = ''' || schema_name || '''' bulk collect into toggled_triggers;
        if toggled_triggers.count <> 0 then
            for i in toggled_triggers.first ..  toggled_triggers.last
            loop
                begin
                    v_sql := 'alter trigger ' || schema_name || '.'
                        || toggled_triggers(i).trigger_name
                        || ' ' || task;
                        
                    --dbms_output.put_line(v_sql);
                    execute immediate v_sql;
                exception
                    when others then
                        err_msg := SUBSTR(SQLERRM(SQLCODE),1,100);
                        dbms_output.put_line('ERROR: Cannot ' || task
                            || ' trigger: ' || toggled_triggers(i).trigger_name);
                        dbms_output.put_line('Error number = ' || SQLCODE);
                        dbms_output.put_line('Error message = ' || err_msg);
                end;
            end loop i;
        else
            dbms_output.put_line('No ' || key_type || ' constraints to ' || task || ' for ' || schema_name);
        end if;
    end;
    
    if upper(task)='ENABLE' then
        execute immediate 'delete from dms_trigger where owner = ''' || schema_name || '''';
    end if;
end toggle_triggers;
/

--execute toggle_triggers('KCOEUS', 'DISABLE')
--/
--execute admin.toggle_triggers('KCOEUS', 'ENABLE')
--/
