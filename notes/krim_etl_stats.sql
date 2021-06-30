create or replace procedure check_last_etl (
    i_month in number,
    i_day in number,
    i_year in number
) 
authid current_user is
begin
    declare
        v_stats_table varchar2(20) := 'krim_etl_stats';
        v_field_list varchar2(200) := 'last_updt_dt as updated, ' || '  to_char( last_updt_dt, ''dd-mon-yy hh24:mi:ss'' ) as updated_time ';
        v_where_clause varchar2(300) := 'where ' ||
            '  extract(month FROM last_updt_dt) = ' || i_month || ' and ' ||
            '  extract(day FROM last_updt_dt) = ' || i_day || ' and ' ||
            '  extract(year FROM last_updt_dt) = ' || i_year;
    begin
        begin
            execute immediate 'drop table ' || v_stats_table;
        exception when others then
            if SQLCODE = -942 then null; else raise; end if;
        end;
        
        execute immediate 'create table ' || v_stats_table || ' (
            table_name varchar2 (50 byte) not null enable, 
            entity_id varchar2(40 byte), 
            updated date not null enable, 
            updated_time varchar2 (50 byte) not null enable
        )';
        
        execute immediate 'truncate table ' || v_stats_table;
    
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_prncpl_t'', prncpl_id as pid, ' || v_field_list ||
            'from kcoeus.krim_prncpl_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_addr_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_addr_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_email_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_email_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_nm_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_nm_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_phone_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_phone_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_priv_pref_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_priv_pref_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_bio_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_bio_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_afltn_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_afltn_t ' || v_where_clause;
        
        execute immediate '' ||
            'insert into ' || v_stats_table || ' select ''krim_entity_emp_info_t'', entity_id as pid, ' || v_field_list ||
            'from kcoeus.krim_entity_emp_info_t ' || v_where_clause;
    end;        
end check_last_etl;
/

execute check_last_etl(8, 20, 2020);
/

select table_name, count(entity_id) as changes
from krim_etl_stats
group by table_name;
/