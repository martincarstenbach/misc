/*
    Copyright 2026 Martin Bach

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in 
    compliance with the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is 
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
    See the License for the specific language governing permissions and limitations under the License.

    File:           capture_session_details.sql
    Purpose:        a simple procedure that captures data at a very low level for intermediate
                    performance troubleshooting
    Requirements:   Oracle 19c or later

    Usage:

    - refer to capture_session_details.md for instructions
    - do NOT run this script without a purge routine in place!
    
    Version History
    
        260429      initial version
*/

create table ash_hist
partition by range (sample_time)
interval( numtodsinterval(1,'day'))
(partition
    p1 values less than (timestamp' 2026-01-01 00:00:00')
) as
select
    *
from
    sys.gv_$active_session_history;

create table gv_session_hist
partition by range (sample_time)
interval( numtodsinterval(1,'day'))
(partition p1 values less than (timestamp' 2026-01-01 00:00:00'))
as
with amended_data as (
  select
    sys_extract_utc ( systimestamp ) as sample_time,
    s.*
  from sys.gv_$session s
)
select * from amended_data;

create or replace package activity_diagnostic_pkg as

  -- Snapshot cadence constants used by scheduler definitions.
    c_snap_interval_gv_session_seconds constant pls_integer := 180;
    c_snap_interval_ash_seconds constant pls_integer := 3600;

  -- Capture incremental ASH rows from GV$ACTIVE_SESSION_HISTORY into ASH_HIST.
    procedure capture_ash_snapshot;

  -- Capture a point-in-time GV$SESSION snapshot into GV_SESSION_HIST.
    procedure capture_sessions_snapshot;

  -- (Re)create scheduler jobs for ASH capture, session capture, and partition purge.
    procedure schedule;

  -- drop all scheduled jobs
    procedure unschedule;

end activity_diagnostic_pkg;
/


create or replace package body activity_diagnostic_pkg as

  -- Module name written to V$SESSION via DBMS_APPLICATION_INFO during package activity.
    c_module_name constant varchar2(100) := 'diagnostics data gathering';

    procedure capture_ash_snapshot as
        l_max_recorded timestamp;
    begin
    -- Tag this session so package-generated activity can be excluded from capture.
        dbms_application_info.set_module(c_module_name, 'capture ASH data');

    -- Determine the latest captured ASH sample time (if any).
        select
            max(sample_time)
        into l_max_recorded
        from
            ash_hist;

    -- Append only rows newer than the watermark; keep NULL module rows.
        insert /*+ append */ into ash_hist
            select
                *
            from
                sys.gv_$active_session_history
            where
                    sample_time > nvl(l_max_recorded, timestamp '2026-01-01 00:00:00')
                and ( module is null
                      or module <> c_module_name );

    -- Lightweight runtime visibility for manual execution. Requires "set serveroutput on"
        dbms_output.put_line('Copied '
                             || sql%rowcount || ' rows into ASH_HIST');

    -- Commit each snapshot batch as an independent unit of work.
        commit;

    -- Clear module/action markers after successful completion.
        dbms_application_info.set_module(null, null);
    exception
        when others then
      -- Always clear module/action markers before propagating errors.
            dbms_application_info.set_module(null, null);
            raise;
    end capture_ash_snapshot;

    procedure capture_sessions_snapshot as
    begin
    -- Tag this session so package-generated activity can be excluded from capture.
        dbms_application_info.set_module(c_module_name, 'capture GV$SESSION data');

    -- Persist a UTC-timestamped full session snapshot.
        insert /*+ append */ into gv_session_hist
            select
                systimestamp at time zone 'UTC' as sample_time,
                s.*
            from
                sys.gv_$session s
            where
                ( s.module is null
                  or s.module <> c_module_name );

    -- Lightweight runtime visibility for manual execution. Requires "set serveroutput on"
        dbms_output.put_line('Copied '
                             || sql%rowcount || ' rows into GV_SESSION_HIST');

    -- Commit each snapshot batch as an independent unit of work.
        commit;

    -- Clear module/action markers after successful completion.
        dbms_application_info.set_module(null, null);
    exception
        when others then
      -- Always clear module/action markers before propagating errors.
            dbms_application_info.set_module(null, null);
            raise;
    end capture_sessions_snapshot;

    procedure schedule as
    begin
    -- Drop existing jobs to make scheduling idempotent.
        unschedule;

    -- Hourly ASH snapshot capture in UTC. Adjust frequency by changing package constants
        dbms_scheduler.create_job(
            job_name        => 'CAPTURE_ASH_SNAPSHOT_JOB',
            job_type        => 'STORED_PROCEDURE',
            job_action      => 'ACTIVITY_DIAGNOSTIC_PKG.CAPTURE_ASH_SNAPSHOT',
            start_date      => systimestamp at time zone 'UTC',
            repeat_interval => 'FREQ=SECONDLY;INTERVAL=' || c_snap_interval_ash_seconds,
            enabled         => true,
            auto_drop       => false,
            comments        => 'Capture ASH snapshot every hour (UTC)'
        );

    -- Session snapshot capture every 180 seconds in UTC. Ajust frequency by changing package constants
        dbms_scheduler.create_job(
            job_name        => 'CAPTURE_SESSIONS_SNAPSHOT_JOB',
            job_type        => 'STORED_PROCEDURE',
            job_action      => 'ACTIVITY_DIAGNOSTIC_PKG.CAPTURE_SESSIONS_SNAPSHOT',
            start_date      => systimestamp at time zone 'UTC',
            repeat_interval => 'FREQ=SECONDLY;INTERVAL=' || c_snap_interval_gv_session_seconds,
            enabled         => true,
            auto_drop       => false,
            comments        => 'Capture GV$SESSION snapshot every 180 seconds (UTC)'
        );

    end schedule;

    procedure unschedule as
    begin
    -- Drop existing jobs 
        begin
            dbms_scheduler.drop_job('CAPTURE_ASH_SNAPSHOT_JOB',
                                    force => true);
        exception
            when others then
        -- Ignore only "job does not exist"; re-raise everything else.
                if sqlcode != -27475 then
                    raise;
                end if;
        end;

        begin
            dbms_scheduler.drop_job('CAPTURE_SESSIONS_SNAPSHOT_JOB',
                                    force => true);
        exception
            when others then
        -- Ignore only "job does not exist"; re-raise everything else.
                if sqlcode != -27475 then
                    raise;
                end if;
        end;

    end unschedule;

end activity_diagnostic_pkg;
/

select
    'DONE. Now make sure you implement a purge procedure to delete old partitions'
from
    dual;