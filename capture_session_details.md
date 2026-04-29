# Activity Diagnostic Data Capture

This directory contains an Oracle Database setup script for collecting local diagnostic history from dynamic performance views.

The script creates:

- `ASH_HIST`: a range-partitioned history table populated from `SYS.GV_$ACTIVE_SESSION_HISTORY`.
- `GV_SESSION_HIST`: a range-partitioned history table populated from `SYS.GV_$SESSION`.
- `ACTIVITY_DIAGNOSTIC_PKG`: a PL/SQL package for manual captures and scheduler job management.

## Prerequisites

Run the script in the schema that should own the history tables and scheduler jobs. That schema needs:

- `CREATE TABLE`
- `CREATE PROCEDURE`
- `CREATE JOB`
- Tablespace quota for the captured history data
- Direct `SELECT` grants on:
  - `SYS.GV_$ACTIVE_SESSION_HISTORY`
  - `SYS.GV_$SESSION`

For stored PL/SQL, grants on the `SYS.GV_$...` views must be direct grants, not only through a role.

Example grants, run as a privileged DBA user:

```sql
grant create table to &amp;diagnostics_user;
grant create procedure to &amp;diagnostics_user;
grant create job to &amp;diagnostics_user;

grant select on sys.gv_$active_session_history to &amp;diagnostics_user;
grant select on sys.gv_$session to &amp;diagnostics_user;
```

Access to Active Session History may require appropriate Oracle licensing. Confirm the licensing position before enabling regular ASH capture.

## Installation

Connect as the target owner schema and run:

```sql
@setup.sql
```

The script immediately creates the two history tables using `CREATE TABLE AS SELECT`, so the initial contents are copied from the current contents of the source views at installation time.

The script does not start the scheduler jobs automatically. After installation, if desired, enable recurring collection with:

```sql
begin
  activity_diagnostic_pkg.schedule;
end;
/
```

Use the regular Oracle Database Scheduler views to monitor progress, success and any potential messages.

## Capture Cadence

The package constants define the default schedule:

- ASH capture: every `3600` seconds.
- `GV$SESSION` capture: every `180` seconds.

To change the cadence defaults, edit the constants in `ACTIVITY_DIAGNOSTIC_PKG` inside `setup.sql`, then rerun the package definition and call `schedule` again.

## Manual Operations

Capture ASH rows newer than the latest row already stored in `ASH_HIST`:

```sql
begin
  activity_diagnostic_pkg.capture_ash_snapshot;
end;
/
```

Capture a point-in-time `GV$SESSION` snapshot:

```sql
begin
  activity_diagnostic_pkg.capture_sessions_snapshot;
end;
/
```

Disable all package-managed scheduler jobs:

```sql
begin
  activity_diagnostic_pkg.unschedule;
end;
/
```

## Verification

Check whether the package compiled successfully:

```sql
select object_name, subobject_name, object_type, status
from user_objects
where object_name in ('ACTIVITY_DIAGNOSTIC_PKG', 'ASH_HIST', 'GV_SESSION_HIST')
order by object_type, object_name;
```

Check scheduler jobs:

```sql
select job_name, enabled, state, repeat_interval
from user_scheduler_jobs
where job_name in (
  'CAPTURE_ASH_SNAPSHOT_JOB',
  'CAPTURE_SESSIONS_SNAPSHOT_JOB'
)
order by job_name;
```

Check individual executions:

```sql
select log_date, job_name, status, error#, errors, output
from user_scheduler_job_run_details
where job_name in  (
  'CAPTURE_ASH_SNAPSHOT_JOB',
  'CAPTURE_SESSIONS_SNAPSHOT_JOB'
)
order by job_name, log_date;
```

Check captured row counts:

```sql
select count(*), to_char(sample_time, 'dd.mm.yyyy hh24') ash_hist_rows_per_day from ash_hist group by to_char(sample_time, 'dd.mm.yyyy hh24') order by 2

select count(*), sample_time as gv_session_hist_rows from gv_session_hist group by sample_time;
```

Check partition growth:

```sql
select table_name, partition_name, partition_position, high_value
from user_tab_partitions
where table_name in ('ASH_HIST', 'GV_SESSION_HIST')
order by table_name, partition_position;
```

Should you need to, remove a partition using the `alter table statement` (-&gt; [docs](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/maintenance-partition-tables-indexes.html#GUID-BAFFE31C-07A2-4ED6-BDCF-8ECB79D7FE7D))

## Reinstallation Notes

`setup.sql` is not fully idempotent. The scheduler setup procedure is idempotent, but the table creation statements will fail if `ASH_HIST` or `GV_SESSION_HIST` already exist. This is done on purpose to avoid data loss. The errors thrown during the create table statements can be ignored _when reinstalling_.

```sql
begin
  activity_diagnostic_pkg.unschedule;
end;
/

drop package activity_diagnostic_pkg;
```

Then rerun, ignoring the _ORA-00955: name is already used by an existing object_ error

```sql
@setup.sql
```

## Operational Notes

- Snapshot procedures tag their own sessions with module name `diagnostics data gathering` and exclude that module from captured data.
- `ASH_HIST` captures only ASH rows newer than the current maximum `SAMPLE_TIME` already stored.
- `GV_SESSION_HIST` captures a complete current session snapshot each time it runs and adds a UTC `SAMPLE_TIME`.
- Both history tables are interval-partitioned by `SAMPLE_TIME` with one-day intervals.
- Partition maintenance is a manual process, so make sure you implement a purge procedure and run it at regular intervals
- Both tables can optionally be compressed
