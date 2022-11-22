create or replace function table_exists (
    table_name varchar2, 
    owner_name varchar2 default null
) 
return boolean 
is
begin
    declare
        v_count number;
        v_owner_name varchar2(64);
    begin
        if owner_name is null then
            execute immediate 'select sys_context(''USERENV'', ''CURRENT_USER'') from dual' into v_owner_name;
        else
            v_owner_name := owner_name;
        end if;

        execute immediate 
            'select count(*) from dba_tables where table_name = ''' ||
            upper(table_name) ||
            ''' and owner = ''' ||
            upper(v_owner_name) || '''' into v_count;
        return not v_count = 0;
    end;
end table_exists;
/


create or replace procedure populate_permanently_disabled_key_table (
    schema_name in varchar2,
    key_type in varchar2
)
authid current_user is
begin
    -- Copy a table that lists all source database foreign keys that were originally disabled and should ALWAYS remain so.
    -- This table should pre-exist in the source database schema having been created with:
    -- create table DMS_FK_PERMANENTLY_DISABLED as
    -- select owner, table_name, constraint_name 
    --     from sys.all_constraints 
    --     where constraint_type = 'R'
    --     and owner in ('KCOEUS', 'KCRMPROC', 'KULUSERMAINT', 'SAPBWKCRM', 'SAPETLKCRM', 'SNAPLOGIC')
    --     and status = 'DISABLED'; 

    declare 
        v_sql varchar2(200);
        v_disabled_fk_table varchar(32) := 'DMS_FK_PERMANENTLY_DISABLED';
        v_invalid_entry exception;
    begin
        -- Validate parameters
        if (upper(key_type)!='FK' and upper(key_type)!='PK') then
            raise_application_error(-20000, 'Invalid key_type parameter! expecting ''FK'' or ''PK''');
        end if;

        if not table_exists(v_disabled_fk_table) then
            if table_exists(v_disabled_fk_table, 'KCOEUS') then
                execute immediate 'create table ' || v_disabled_fk_table || ' as select * from KCOEUS.' || v_disabled_fk_table;
            else
                raise_application_error(-20001, 'Table not found in this schema or KCOEUS schema: ' || v_disabled_fk_table);
            end if;
        end if;
    end;
end populate_permanently_disabled_key_table;
/


create or replace procedure populate_constraint_toggle_table (
    schema_name in varchar2,
    key_type in varchar2,
    task in varchar2
) 
authid current_user is
begin
    declare
        v_count number;
        v_sql varchar2(400);
        v_key_table varchar2(64);
        v_log_table varchar2(64);
        v_err_table varchar2(64);
        v_equals varchar2(2) := '!=';
        v_status varchar(10) := 'ENABLED';
        v_invalid_entry exception;
    begin
        -- Validate parameters
        if (upper(key_type)!='FK' and upper(key_type)!='PK') then
            raise_application_error(-20000, 'Invalid key_type parameter! expecting ''FK'' or ''PK''');
        end if;
        if (upper(task)!='ENABLE' and upper(task)!='DISABLE') then
            raise_application_error(-20001, 'Invalid task parameter! expecting ''DISABLE'' or ''ENABLE''');
        end if;

        populate_permanently_disabled_key_table(schema_name, key_type);
        
        if upper(key_type)='FK' then
            v_equals := '=';
        end if;
        
        if upper(task)='ENABLE' then
            v_status := 'DISABLED';
        end if;

        -- Baseline select for getting a schemas foreign key constraints
        v_sql := '' ||
        'select owner, table_name, constraint_name ' ||
        'from sys.all_constraints c ' ||
        'where ' ||
            'c.constraint_type ' || v_equals || '''R'' and ' ||
            'c.owner = ''' || schema_name || ''' and ' ||
            'c.status = ''' || v_status || '''';
            if upper(key_type)='FK' then 
                v_sql := v_sql || 
                    ' and not exists (' ||
                    'select null from DMS_FK_PERMANENTLY_DISABLED d ' ||
                    'where ' ||
                        'd.CONSTRAINT_NAME = c.CONSTRAINT_NAME and ' ||
                        'd.OWNER = c.OWNER and ' ||
                        'd.TABLE_NAME = c.TABLE_NAME ' ||
                    ')';
            end if;
        
        v_key_table := 'dms_' || key_type;        
        v_log_table := v_key_table || '_last_run';
        v_err_table := v_key_table || '_last_run_errors';
                
        -- Determine if the dms_(f|p)k table exists. (dms_(f|p)k is used to log which foreign/primary key constraints will be or have been disabled)
        if not table_exists(v_key_table) then            
            dbms_output.put_line('Creating table ' || v_key_table);
            execute immediate 'create table ' || v_key_table || ' as ' || v_sql;
        else
            execute immediate 'select count(*) from ' || v_key_table || ' where owner = ''' || schema_name || '''' into v_count;
            if v_count=0 then
                -- dms_(f|p)k already exists but has no entries for the specified schemas foreign keys, so insert them.
                dbms_output.put_line('Inserting records into ' || v_key_table);
                execute immediate 'insert into ' || v_key_table || ' ' || v_sql;
            else
                dbms_output.put_line('The ' || v_key_table || ' table already has ' || v_count || ' entries in it.');
            end if;
        end if;
        
        if not table_exists(v_log_table) then
            -- Create an empty clone of the table of keys to change to add successful attempts to
            dbms_output.put_line('Creating table ' || v_log_table);
            execute immediate 'create table ' || v_log_table || ' as select d.*, ''12345678'' as status from ' || v_key_table || ' d where 1=0';
        else
            dbms_output.put_line('Truncating table ' || v_log_table);
            execute immediate 'truncate table ' || v_log_table;
        end if;
        
        if not table_exists(v_err_table) then
            -- Create an empty clone of the table of keys to change to add failed attempts to
            dbms_output.put_line('Creating table ' || v_err_table);
            execute immediate 'create table ' || v_err_table || ' as select d.*, ''1234567'' as task from ' || v_key_table || ' d where 1=0';
            execute immediate 'alter table ' || v_err_table || ' add(SQLCODE number null, SQLERRM varchar(100) null)';
        else
            dbms_output.put_line('Truncating table ' || v_err_table);
            execute immediate 'truncate table ' || v_err_table;
        end if;
    end;
end populate_constraint_toggle_table;
/


-- set serveroutput on;
-- execute populate_constraint_toggle_table('KCOEUS', 'FK', 'DISABLE')
-- /
-- execute populate_constraint_toggle_table('KCRMPROC', 'FK', 'DISABLE')
-- /
-- execute populate_constraint_toggle_table('KULUSERMAINT', 'FK', 'DISABLE')
-- /
-- execute populate_constraint_toggle_table('SAPBWKCRM', 'FK', 'DISABLE')
-- /
-- execute populate_constraint_toggle_table('SAPETLKCRM', 'FK', 'DISABLE')
-- /
-- execute populate_constraint_toggle_table('SNAPLOGIC', 'FK', 'DISABLE')
-- /


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
        v_key_table varchar2(64);
        v_log_table varchar2(64);
        v_err_table varchar2(64);
        err_msg VARCHAR2(100);
    begin
        -- Validate parameters
        if (upper(key_type)!='FK' and upper(key_type)!='PK') then
            raise_application_error(-20000, 'Invalid key_type parameter! expecting ''FK'' or ''PK''');
        end if;
        if (upper(task)!='ENABLE' and upper(task)!='DISABLE') then
            raise_application_error(-20001, 'Invalid task parameter! expecting ''DISABLE'' or ''ENABLE''');
        end if;
        
        populate_constraint_toggle_table(schema_name, key_type, task);
        
        v_key_table := 'dms_' || key_type;        
        v_log_table := v_key_table || '_last_run';
        v_err_table := v_key_table || '_last_run_errors';

        execute immediate 'select * from ' || v_key_table || ' where owner = ''' || schema_name
            || '''' bulk collect into toggled_constraints;
            
        if toggled_constraints.count <> 0 then
            for i in toggled_constraints.first ..  toggled_constraints.last
            loop
                begin
                    v_sql := 'alter table ' || schema_name || '.'
                        || toggled_constraints(i).table_name
                        || ' ' || task || ' constraint '
                        || toggled_constraints(i).constraint_name;
                    execute immediate v_sql;
                        
                    v_sql := 'insert into ' || v_log_table || ' values ('
                        || '''' || toggled_constraints(i).owner || ''', '
                        || '''' || toggled_constraints(i).table_name || ''', '
                        || '''' || toggled_constraints(i).constraint_name || ''', '
                        || '''' || upper(task) || 'D'''
                        || ')';
                    -- DBMS_OUTPUT.PUT_LINE(v_sql);
                    -- return;
                    execute immediate v_sql;
                        
                    commit;
                exception
                    when others then
                        err_msg := SUBSTR(SQLERRM(SQLCODE),1,100);
                        -- dbms_output.put_line('ERROR: Cannot ' || task
                        --     || ' constraint: ' || toggled_constraints(i).constraint_name
                        --     || ' on table: ' || toggled_constraints(i).table_name);
                        -- dbms_output.put_line('Error number = ' || SQLCODE);
                        -- dbms_output.put_line('Error message = ' || err_msg);
                        execute immediate 'insert into ' || v_err_table || ' values ('
                            || '''' || toggled_constraints(i).owner || ''', '
                            || '''' || toggled_constraints(i).table_name || ''', '
                            || '''' || toggled_constraints(i).constraint_name || ''', '
                            || '''' || upper(task) || ''', '
                            || SQLCODE || ', '
                            || '''' || err_msg
                            || ''')';
                        commit;
                end;
            end loop i;
        else
            dbms_output.put_line('No ' || key_type || ' constraints to ' || task || ' for ' || schema_name);
        end if;
    
        if upper(task)='ENABLE' then
            dbms_output.put_line('Removing ' || schema_name || ' entries from ' || v_key_table);
            execute immediate 'delete from ' || v_key_table || ' where owner = ''' || schema_name || '''';
        end if;
    end;
end toggle_constraints;
/

--set serveroutput on;
--execute admin.toggle_constraints('KCOEUS', 'FK', 'DISABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'PK', 'DISABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'PK', 'ENABLE')
--/
--execute admin.toggle_constraints('KCOEUS', 'FK', 'ENABLE')
--/
