-- set serveroutput on;
create or replace procedure populate_constraint_toggle_table (
    schema_name in varchar2,
    key_type in varchar2
) 
authid current_user is
begin
    declare 
        v_count number;
        v_sql varchar2(200);
        v_equals varchar2(2) := '!=';
        v_invalid_entry exception;
    begin
        -- Validate parameters
        if (upper(key_type)!='FK' and upper(key_type)!='PK') then
            raise_application_error(-20000, 'Invalid key_type parameter! expecting ''FK'' or ''PK''');
        end if;
        
        if upper(key_type)='FK' then
            v_equals := '=';
        end if;
        
        -- Baseline select for getting a schemas foreign key constraints
        v_sql := 'select owner, table_name, constraint_name ' ||
            'from sys.all_constraints ' ||
            'where constraint_type ' || v_equals || '''R'' ' ||
            'and owner = ''' || schema_name || ''' ' ||
            'and status = ''ENABLED''';

        -- Determine if the dms_(f|p)k table exists (dms_(f|p)k is used to log which foreign/primary key constraints will be or have been disabled)
        execute immediate 'select count(*) from dba_tables where table_name = ''DMS_' || key_type || ''' and owner = ''ADMIN''' into v_count;
        if v_count=0 then
            execute immediate 'create table dms_' || key_type || ' as ' || v_sql;
        else
            execute immediate 'select count(*) from dms_' || key_type || ' where owner = ''' || schema_name || '''' into v_count;
            if v_count=0 then
                -- dms_(f|p)k already exists but has no entries for the specified schemas foreign keys, so insert them.
                execute immediate 'insert into dms_' || key_type || ' ' || v_sql;
            end if;
        end if;
    end;
end populate_constraint_toggle_table;
/


execute populate_constraint_toggle_table('KCOEUS', 'FK')
/
execute populate_constraint_toggle_table('KCRMPROC', 'FK')
/
execute populate_constraint_toggle_table('KULUSERMAINT', 'FK')
/
execute populate_constraint_toggle_table('SAPBWKCRM', 'FK')
/
execute populate_constraint_toggle_table('SAPETLKCRM', 'FK')
/
execute populate_constraint_toggle_table('SNAPLOGIC', 'FK')
/



create or replace procedure toggle_constraints (
    schema_name in varchar2,
    key_type in varchar2,
    task in varchar2
) 
authid current_user is
begin        
    -- Disable/enable the foreign keys for the schema
    declare
        v_sql varchar2(200);
        type cnt_typ is table of dms_fk%ROWTYPE index by pls_integer;
        toggled_constraints cnt_typ;
        err_msg VARCHAR2(100);
    begin
        -- Validate parameters
        if (upper(key_type)!='FK' and upper(key_type)!='PK') then
            raise_application_error(-20000, 'Invalid key_type parameter! expecting ''FK'' or ''PK''');
        end if;
        if (upper(task)!='ENABLE' and upper(task)!='DISABLE') then
            raise_application_error(-20001, 'Invalid task parameter! expecting ''DISABLE'' or ''ENABLE''');
        end if;
        
        populate_constraint_toggle_table(schema_name, key_type);
        
        execute immediate 'select * from dms_' || key_type || ' where owner = ''' || schema_name
            || '''' bulk collect into toggled_constraints;
            
        if toggled_constraints.count <> 0 then
            for i in toggled_constraints.first ..  toggled_constraints.last
            loop
                begin
                    v_sql := 'alter table ' || schema_name || '.'
                        || toggled_constraints(i).table_name
                        || ' ' || task || ' constraint '
                        || toggled_constraints(i).constraint_name;
                        
                    --DBMS_OUTPUT.PUT_LINE(v_sql);
                    execute immediate v_sql;
                exception
                    when others then
                        err_msg := SUBSTR(SQLERRM(SQLCODE),1,100);
                        dbms_output.put_line('ERROR: Cannot ' || task
                            || ' constraint: ' || toggled_constraints(i).constraint_name
                            || ' on table: ' || toggled_constraints(i).table_name);
                        dbms_output.put_line('Error number = ' || SQLCODE);
                        dbms_output.put_line('Error message = ' || err_msg);
                end;
            end loop i;
        else
            dbms_output.put_line('No ' || key_type || ' constraints to ' || task || ' for ' || schema_name);
        end if;
    end;
    
    if upper(task)='ENABLE' then
        execute immediate 'delete from dms_' || key_type || ' where owner = ''' || schema_name || '''';
    end if;
end toggle_constraints;
/

--execute admin.toggle_constraints('KCOEUS', 'FK', 'DISABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'PK', 'DISABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'PK', 'ENABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'FK', 'ENABLE')
--/
