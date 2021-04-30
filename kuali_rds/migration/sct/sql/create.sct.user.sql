


-- ------------ Write CREATE-USER-stage scripts -----------

CREATE USER AWS_SCHEMA_CONV
    IDENTIFIED BY user_password
    DEFAULT TABLESPACE KUALI_DATA
    TEMPORARY TABLESPACE TEMP
    PROFILE NOEXPIRE
/




 




-- ------------ Write CREATE-GRANTED-ROLE-stage scripts -----------

GRANT SCHEDULER_ADMIN TO AWS_SCHEMA_CONV
/




 




-- ------------ Write CREATE-SYSTEM-PRIVILEGE-stage scripts -----------

GRANT CREATE SESSION TO AWS_SCHEMA_CONV
/



GRANT SELECT ANY DICTIONARY TO AWS_SCHEMA_CONV
/




 




-- ------------ Write CREATE-OBJECT-PRIVILEGE-stage scripts -----------

GRANT SELECT ON SYS.USER$ TO AWS_SCHEMA_CONV
/




 

