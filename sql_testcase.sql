/*
    Copyright 2021 Martin Bach

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in 
    compliance with the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is 
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
    See the License for the specific language governing permissions and limitations under the License.

    File:           sql_testcase.sql
    Purpose:        a simple script to create a SQL testcase for Oracle 19c
    Requirements:   Oracle 19c, might work with earlier versions as well, not tested

    Usage:

    - invoke the script and answer the prompts

      @get_prefs soe orders
    
        210803      initial version

    References:

    - https://docs.oracle.com/en/database/oracle/oracle-database/18/tgsql/sql-test-case-builder.html
*/

PROMPT  
PROMPT  Create a SQL test case using the Test Case Generator
PROMPT

SET verify off long 1000000 longchunk 120 lines 120 trimspool on pages 0

accept v_sqlid prompt 'enter SQL ID: '
accept v_phv prompt 'enter plan hash value (enter % for all): '
accept v_dir_path prompt 'enter the file system location where the test case is exported to: '

-- create the directory on the file system
HOST mkdir -p '&v_dir_path'

whenever sqlerror exit 
create or replace directory test_case_dir as '&v_dir_path'
/

PROMPT
PROMPT Generating a SQL test case for SQL ID &v_sqlid ...
PROMPT 

-- create the test case
VAR tc clob
whenever sqlerror continue

begin
  DBMS_SQLDIAG.EXPORT_SQL_TESTCASE (
    directory                => 'TEST_CASE_DIR',
    sql_id                   => '&v_sqlid',
    plan_hash_value          => case when '&v_phv' = '%' then null else '&v_phv' end,
    exportEnvironment        => TRUE,
    exportMetadata           => TRUE,
    exportData               => FALSE,
    exportPkgbody            => TRUE,
    testcase_name            => 'TC_&v_sqlid._', 
    testcase                 => :tc);
end;
/

PROMPT
PROMPT Finished generating your test case for SQL ID &v_sqlid ...
PROMPT 

print :tc