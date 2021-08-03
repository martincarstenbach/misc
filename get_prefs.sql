/*
    Copyright 2021 Martin Bach

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in 
    compliance with the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is 
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
    See the License for the specific language governing permissions and limitations under the License.

    File:           get_prefs.sql
    Purpose:        a simple script to print all possible table preferences for a given table
    Requirements:   Oracle 19c
    See also:       https://martincarstenbach.wordpress.com/2020/02/13/printing-all-table-preferences-affecting-dbms_stats-gather_table_stats/

    Usage:

    - call the script passing the owner and table name

      @get_prefs soe orders
    
        210803      initial version
*/

set serveroutput on 
set verify off

-- check if the object exists
whenever sqlerror exit
select 'Printing DBMS_STATS preferences for table ' || upper(sys.dbms_assert.sql_object_name('&1..&2')) get_prefs from dual;
whenever sqlerror continue

-- print table preferences
declare 
    v_version varchar2(100);
    v_compat  varchar2(100);

    type prefs_t is table of varchar2(100);

    v_prefs_19c prefs_t := prefs_t(
        'APPROXIMATE_NDV_ALGORITHM',
        'AUTO_STAT_EXTENSIONS',
        'AUTO_TASK_STATUS',
        'AUTO_TASK_MAX_RUN_TIME',
        'AUTO_TASK_INTERVAL',
        'CASCADE',
        'CONCURRENT',
        'DEGREE',
        'ESTIMATE_PERCENT',
        'GLOBAL_TEMP_TABLE_STATS',
        'GRANULARITY',
        'INCREMENTAL',
        'INCREMENTAL_STALENESS',
        'INCREMENTAL_LEVEL',
        'METHOD_OPT',
        'NO_INVALIDATE',
        'OPTIONS',
        'PREFERENCE_OVERRIDES_PARAMETER',
        'PUBLISH',
        'STALE_PERCENT',
        'STAT_CATEGORY',
        'TABLE_CACHED_BLOCKS'
    );

    procedure print_prefs(pi_prefs prefs_t) as
        v_value varchar2(100);
    begin   
        for i in pi_prefs.first .. pi_prefs.last loop
            v_value := sys.dbms_stats.get_prefs(
                pname => pi_prefs(i),
                ownname => sys.dbms_assert.schema_name(upper('&1')),
                tabname => sys.dbms_assert.simple_sql_name('&2')
            );

        sys.dbms_output.put_line(rpad(pi_prefs(i), 50) || ': ' || v_value);
        end loop;
    end;

begin   
    sys.dbms_utility.db_version(v_version, v_compat);

    if v_version = '19.0.0.0.0' then
        print_prefs(v_prefs_19c);
    else
        raise_application_error(-20001, 'Oracle ' || v_version || ' not yet supported by this script');
    end if;

end;
/

set serveroutput off 
set verify on