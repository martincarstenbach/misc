/*
    Copyright 2025 Martin Bach

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in 
    compliance with the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is 
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
    See the License for the specific language governing permissions and limitations under the License.

    File:           flush_sql.sql
    Purpose:        a simple script to flush a single SQL ID from the shared pool
    Requirements:   Oracle 11.1 or later, tested on 21c only, use at your own risk

    Usage:

    - invoke the script and follow the prompts.
    - have the SQL ID to be purged available

      @flush_sql <sqlID>
    
    Version History
    
        221219      initial version
    
    Reference
    - https://martincarstenbach.wordpress.com/2009/11/26/selectively-purging-the-shared-pool/
*/

accept l_sql_id prompt 'enter a SQL ID to be purged from the shared pool: ' 

DECLARE
    l_version    VARCHAR2(50);
    l_compatible VARCHAR2(50);
    l_name       VARCHAR2(255);
BEGIN

    -- sanity checking, the script requires Oracle 11.1 or later
    dbms_utility.db_version(
        l_version,
        l_compatible
    );

    IF TO_NUMBER ( regexp_substr(l_compatible, '[0-9]+') ) <= 11 THEN
        raise_application_error(
            -20001,
            'this script requires *.compatible to be set to at least Oracle 11.1'
        );
    END IF;

    BEGIN
        SELECT
            address
            || ','
            || hash_value
        INTO l_name
        FROM
            v$sqlarea
        WHERE
            sql_id LIKE '&l_sql_id';
    EXCEPTION
        WHEN no_data_found THEN
            raise_application_error(-20002, 'No cursor found in the shared pool for SQL ID &l_sql_id');
    END;

    sys.dbms_shared_pool.purge(
        name  => l_name,
        flag  => 'C',
        heaps => 1
    );
END;
/
