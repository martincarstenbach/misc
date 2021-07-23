/*
    Copyright 2021 Martin Bach

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in 
    compliance with the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is 
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
    See the License for the specific language governing permissions and limitations under the License.

    File:           gen_awr_rpts.sql   
    Purpose:        a simple tool querying the Automatic Workload Repository and generates (hourly) reports
                    per instance and global (in case of Real Application Clusters). The code iterates over
                    all the snapshots recorded. If your snapshot interval is <> 60 minutes it'll create a
                    _lot_ of reports.
    Requirements:   Should run on 10.2 and later, tested with 19.11.0 on Oracle Linux 8
                    Can be run from either the database host or a client (instant client should suffice). 
                    User executing it must have appropriate access to the database's dictionary
                    Built using SQL*Plus, although the script might run with sqlcl, too.
                    Has been tested on Linux, should also run on MacOS. There are limitations when running on 
                    Windows (resulting AWR reports aren't automatically zipped for email transport)

    Usage:

    - connect to the database with an admin user using sqlplus
    - run this script (it will generate a helper script with the actual commands)
    - review the helper script
    - run the helper script once you are happy it does exactly what you want it to do

    TODO list:

    - add support for Pluggable Databases (PDBs)

    Version history:
    
        210707      initial version
*/

-- global variables
DEFINE v_output_format = 'html'

-- global settings

set verify off

-- the script requires a license for Enterprise Edition + Diagnostics Pack

accept v_ee_diag prompt  'Enter "y" if this database is an EE system licensed with the Diagnostics Pack: '
whenever sqlerror exit 1
begin
    if lower('&v_ee_diag') != 'y' then
        raise_application_error(-20001, 'System not licensed appropriately for this script, aborting');
    end if;
end;
/

-- get database metadata for use with dbms_workload_repository

column dbid new_value v_dbid
column cdb new_value v_cdb
column instance_count new_value v_instance_count
select dbid, cdb from v$database;

select count(*) as instance_count from gv$instance;
 
-- perform a little sanity checking: this script only works for NCDBs or the CDB root (see TODO list)

begin
    if '&v_cdb.' = 'YES' and sys_context('userenv', 'con_name') != 'CDB$ROOT' then
        raise_application_error(-20002, 'This script cannot be executed in a PDB, aborting');
    end if;
end;
/

-- prompt the user to provide a date range 

prompt
prompt Enter data range to collect AWR reports from and to
prompt 
accept v_start_date prompt 'Collect AWR reports from this date [dd.mm.yyyy]: '
accept v_end_date prompt 'Collect AWR reports until this date [dd.mm.yyyy]: '

prompt 
prompt About to create the helper script...

-- write the helper script

column end_interval_time for a30
set termout off linesize 800 pages 0 verify off heading off trimspool on trimout on feedback 0
spool helper.sql replace

prompt set termout off pagesize 0 heading off linesize 1000 trimspool on trimout on tab off

-- instance-specific AWR reports

WITH awr_reports AS (
    SELECT
        snap_id          start_snap_id,
        LEAD(snap_id, 1, NULL)
        OVER(PARTITION BY instance_number
             ORDER BY snap_id
        )                end_snap_id,
        end_interval_time,
        instance_number  inst_num
    FROM
        dba_hist_snapshot
    WHERE
        end_interval_time BETWEEN TO_DATE('&v_start_date.', 'dd.mm.yyyy') AND (TO_DATE('&v_end_date.', 'dd.mm.yyyy') + 1)
        AND dbid = &v_dbid
    ORDER BY
        snap_id
)
SELECT
    'spool awr_report_&v_dbid._' || inst_num || '_' || start_snap_id || '_' || end_snap_id || '.&v_output_format' || chr(10) ||
    'select output from table(DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_&v_output_format.('
    || 'l_dbid => &v_dbid., l_inst_num => ' || inst_num
    || ', l_bid => '
    || start_snap_id
    || ', l_eid => '
    || end_snap_id
    || '));'
    || chr(10) || 'spool off' || chr(10)
FROM
    awr_reports
WHERE
    end_snap_id IS NOT NULL;

-- RAC reports

WITH awr_global_reports AS (
SELECT
    snap_id as start_snap_id,
    LEAD(snap_id, 1, NULL)
    OVER(
        ORDER BY snap_id
    )                          AS end_snap_id,
    MAX(end_interval_time)     AS end_interval_time
FROM
    dba_hist_snapshot
WHERE
    end_interval_time BETWEEN TO_DATE('&v_start_date.', 'dd.mm.yyyy') AND (TO_DATE('&v_end_date.', 'dd.mm.yyyy') + 1)
    AND dbid = &v_dbid
GROUP BY
    snap_id
ORDER BY
    snap_id
)
SELECT
    'spool awr_global_report_&v_dbid._'|| start_snap_id || '_' || end_snap_id || '.&v_output_format' || chr(10) ||
    'select output from table(DBMS_WORKLOAD_REPOSITORY.AWR_GLOBAL_REPORT_&v_output_format.('
    || 'l_dbid => &v_dbid., l_inst_num => ''''' 
    || ', l_bid => '
    || start_snap_id
    || ', l_eid => '
    || end_snap_id
    || '));'
    || chr(10) || 'spool off' || chr(10)
FROM
    awr_global_reports
WHERE
    end_snap_id IS NOT NULL
    and &v_instance_count > 1;

-- add the newly created AWR reports into a zip archive

select 'set termout on' || chr(10) ||
    'prompt adding AWR reports to a zip archive, deleting the input in the process' || chr(10) ||
    'host zip awr_reports_$(hostname)_&v_dbid._$(date +%Y%m%d).zip awr*&v_dbid.*.html'  || chr(10) ||
    'host rm -v awr*&v_dbid.*.html'
from dual;

set termout on
spool off

prompt Helper script created. Review helper.sql and execute it once you are satisfied with its contents
prompt 
