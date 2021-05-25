set serveroutput on; 
declare 
  V_TABL_NM ALL_TABLES.TABLE_NAME%TYPE; 
  ROW_COUNT INT;
    
BEGIN 
    FOR GET_TABL_LIST IN ( 
        SELECT TABLE_NAME FROM ALL_TABLES 
        WHERE TABLESPACE_NAME = 'KUALI_DATA' AND OWNER = 'KCOEUS'   
        ORDER BY TABLE_NAME
    )LOOP 
        V_TABL_NM := GET_TABL_LIST.TABLE_NAME;
        EXECUTE IMMEDIATE 'select count(*) from "KCOEUS"."' || V_TABL_NM || '"' INTO ROW_COUNT;
        DBMS_OUTPUT.PUT_LINE(V_TABL_NM || ': ' || ROW_COUNT);
    END LOOP; 
END;
/