--Useful queries for DBA

--Finding the blocking statement in Sql Server

SELECT
db.name DBName,
tl.request_session_id,
wt.blocking_session_id,
OBJECT_NAME(p.OBJECT_ID) BlockedObjectName,
tl.resource_type,
h1.TEXT AS RequestingText,
h2.TEXT AS BlockingTest,
tl.request_mode
FROM sys.dm_tran_locks AS tl
INNER JOIN sys.databases db ON db.database_id = tl.resource_database_id
INNER JOIN sys.dm_os_waiting_tasks AS wt ON tl.lock_owner_address = wt.resource_address
INNER JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id
INNER JOIN sys.dm_exec_connections ec1 ON ec1.session_id = tl.request_session_id
INNER JOIN sys.dm_exec_connections ec2 ON ec2.session_id = wt.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(ec1.most_recent_sql_handle) AS h1
CROSS APPLY sys.dm_exec_sql_text(ec2.most_recent_sql_handle) AS h2
GO

--***********************************************************************************************
--Finding the user who running the query in the server

SELECT
s.session_id AS SessionID,
 s.login_time AS LoginTime,
 s.[host_name] AS HostName,
 s.[program_name] AS ProgramName,
 s.login_name AS LoginName,
 s.[status] AS SessionStatus,
 st.text AS SQLText,
 (s.cpu_time / 1000) AS CPUTimeInSec,
 (s.memory_usage * 8) AS MemoryUsageKB,
 (CAST(s.total_scheduled_time AS FLOAT) / 1000) AS TotalScheduledTimeInSec,
 (CAST(s.total_elapsed_time AS FLOAT) / 1000) AS ElapsedTimeInSec,
 s.reads AS ReadsThisSession,
 s.writes AS WritesThisSession,
 s.logical_reads AS LogicalReads,
 CASE s.transaction_isolation_level
 WHEN 0 THEN 'Unspecified'
 WHEN 1 THEN 'ReadUncommitted'
 WHEN 2 THEN 'ReadCommitted'
 WHEN 3 THEN 'Repeatable'
 WHEN 4 THEN 'Serializable'
 WHEN 5 THEN 'Snapshot'
 END AS TransactionIsolationLevel,
 s.row_count AS RowsReturnedSoFar,
 c.net_transport AS ConnectionProtocol,
 c.num_reads AS PacketReadsThisConnection,
 c.num_writes AS PacketWritesThisConnection,
 c.client_net_address AS RemoteHostIP,
 c.local_net_address AS LocalConnectionIP
 FROM sys.dm_exec_sessions s INNER JOIN sys.dm_exec_connections c
 ON s.session_id = c.session_id
 CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS st
 WHERE s.is_user_process = 1 and [status]='running'
 ORDER BY ElapsedTimeInSec,LoginTime DESC

--***********************************************************************************************
--Log Removing Query

-- Truncate the log by changing the database recovery model to SIMPLE.
ALTER DATABASE DatabaseName
SET RECOVERY SIMPLE;
GO
-- Shrink the truncated log file to 1 MB.
DBCC SHRINKFILE (Database_log], 1);
GO
-- Reset the database
ALTER DATABASE DatabaseName
SET RECOVERY FULL;
GO

sp_helpdb 'DatabaseName'

--***********************************************************************************************
--LAST BACK UP Timings

SELECT db.name,
case when MAX(b.backup_finish_date) is NULL then 'No Backup' elseconvert(varchar(100),
MAX(b.backup_finish_date)) end AS last_backup_finish_date
FROM sys.databases db LEFT OUTER JOIN msdb.dbo.backupset b ON db.name =b.database_name AND b.type = 'D'  WHERE db.database_id NOT IN (2)  GROUP BYdb.name ORDER BY 2 DESC

--***********************************************************************************************
--PATH WHERE THE BACKUP HAVE BEEN SAVED

SELECT Distinct physical_device_name FROM msdb.dbo.backupmediafamily

***********************************************************************************************
--LIST check the current users, process and session information
sp_who
sp_who2

***********************************************************************************************

--Unlocking a login
--To unlock a SQL Server login, execute the following statement, replacing **** with the desired account password.
ALTER LOGIN [Mary5] WITH PASSWORD = ‘****’ UNLOCK ;
GO
--To unlock a login without changing the password, turn the check policy off and then on again.
ALTER LOGIN [Mary5] WITH CHECK_POLICY = OFF;
ALTER LOGIN [Mary5] WITH CHECK_POLICY = ON;
GO

 --Enabling a disabled login
 ALTER LOGIN Mary5 ENABLE;


--Changing the password of a login
ALTER LOGIN Mary5 WITH PASSWORD = ”;




--Changing the name of a login
ALTER LOGIN Mary5 WITH NAME = John2;




***********************************************************************************************

--Query which has taken more time for executing
      
SELECT TOP 10 obj.name, max_logical_reads, max_elapsed_time
FROM sys.dm_exec_query_stats a
CROSS APPLY sys.dm_exec_sql_text(sql_handle) hnd
INNER JOIN sys.sysobjects obj on hnd.objectid = obj.id

ORDER BY max_logical_reads DESC

--***********************************************************************************************
--Restore SQL table backup using BCP (BULK COPY PROGRAM)

BULK INSERT AdventureWorks.Person.Contacts_Restore 
    FROM 'C:\MSSQL\Backup\Contact.Dat'

    WITH (DATAFILETYPE='native'); 

--***********************************************************************************************

/*find no. of stored procedures*/
Select count(*) from sysobjects where xtype = 'P'

--***********************************************************************************************
--Database objects were they were changed last time

select name, crdate, refdate
from sysobjects
order by crdate desc
go

--***********************************************************************************************
--List expensive queries

DECLARE @MinExecutions int;
SET @MinExecutions = 5

SELECT EQS.total_worker_time AS TotalWorkerTime
      ,EQS.total_logical_reads + EQS.total_logical_writes AS TotalLogicalIO
      ,EQS.execution_count As ExeCnt
      ,EQS.last_execution_time AS LastUsage
      ,EQS.total_worker_time / EQS.execution_count as AvgCPUTimeMiS
      ,(EQS.total_logical_reads + EQS.total_logical_writes) / EQS.execution_count 
       AS AvgLogicalIO
      ,DB.name AS DatabaseName
      ,SUBSTRING(EST.text
                ,1 + EQS.statement_start_offset / 2
                ,(CASE WHEN EQS.statement_end_offset = -1 
                       THEN LEN(convert(nvarchar(max), EST.text)) * 2 
                       ELSE EQS.statement_end_offset END 
                 - EQS.statement_start_offset) / 2
                ) AS SqlStatement
      -- Optional with Query plan; remove comment to show, but then the query takes !!much longer time!!
      --,EQP.[query_plan] AS [QueryPlan]
FROM sys.dm_exec_query_stats AS EQS
     CROSS APPLY sys.dm_exec_sql_text(EQS.sql_handle) AS EST
     CROSS APPLY sys.dm_exec_query_plan(EQS.plan_handle) AS EQP
     LEFT JOIN sys.databases AS DB
         ON EST.dbid = DB.database_id     
WHERE EQS.execution_count > @MinExecutions
      AND EQS.last_execution_time > DATEDIFF(MONTH, -1, GETDATE())
ORDER BY AvgLogicalIo DESC
        ,AvgCPUTimeMiS DESC

--*********************************************************************************************** 
/*The sys.dm_db_missing_index_group_stats has these particularly interesting fields:
•	user_seeks: This column tells us how many seek operations would be done over the missing index.
•	user_scans: This column tells us how many scan operations would be done over the missing index.
•	avg_total_user_cost: This column has an average cost for all the queries that would have used the missing index. The “cost” is a ‘unitless’ value in an arbitrary currency, calculated by the query optimizer, but it is useful to know.
•	avg_user_impact: This column has an average percentage by which query cost could drop if we create this missing index.
Now we have enough information to create a query to show us the missing index in the order of the impact their creation will have:
*/	


SELECT TOP 20
 ROUND(s.avg_total_user_cost *
       s.avg_user_impact
        * (s.user_seeks + s.user_scans),0)
                 AS [Total Cost]
 ,d.[statement] AS [Table Name]
 ,equality_columns
 ,inequality_columns
 ,included_columns
FROM sys.dm_db_missing_index_groups g
INNER JOIN sys.dm_db_missing_index_group_stats s
  ON s.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details d
  ON d.index_handle = g.index_handle
ORDER BY [Total Cost] DESC

/*
Auto-growth
Auto-growth is a good feature that ensures that the DBA will never find out that the database stopped because the data or log files hasn’t enough space. Without a doubt, it’s a good practice to keep auto-growth enabled, but you, as a DBA, should retain control over when and why auto-growth happens.
As well as the regular and planned database growth that allows the DBA to calculate days in advance when the auto-growth will happen, there are certain events that can precipitate auto-growth through making large temporary or sudden demands for disk space. Batch processes, for example, can use a large amount of space in data and log files and thereby trigger the auto-growth.
If this happens in the data files, the sudden auto-growth event will cause performance problems for the execution of the batch. The batch that triggered the auto-growth will then suffer performance problems while the auto-growth is happening. Sometimes the person who created the batch hasn’t full knowledge about the database server, probably not even knowing that the batch could run considerably faster if the data file size was sufficient, which would need to be planned in advance.
On the other hand, if the auto-growth happens in the log file, the growth will create new VLFs inside the log. If the log files has too many VLFs then the log backups and database recovery will get slower.
To avoid this, the DBA should always check whether unplanned auto-growth is happening, and if so then identify the reason and adjust the plans for auto-growth.
How do you check on the pattern of file-growth? SQL Server has a default trace that captures information about the file growth. If the default trace is running – and it is by default – you can recover this information.
First you need to recover the path where the trace is storing its files. You can do that with a small query over sys.traces. Next, we need to use the DMF sys.fn_trace_gettable to read the file and return the information as a table.
The query to find out the auto-growth that happened in our server is the following:
*/	
	
DECLARE @path NVARCHAR(260); 
 
SELECT 
@path = REVERSE(SUBSTRING(REVERSE([path]), 
CHARINDEX('\', REVERSE([path])), 260)) + N'log.trc' 
FROM sys.traces 
WHERE is_default = 1; 
 
SELECT 
DatabaseName, 
[FileName], 
SPID, 
Duration, 
StartTime, 
EndTime, 
FileType = CASE EventClass 
WHEN 92 THEN 'Data' 
WHEN 93 THEN 'Log' 
END 
FROM sys.fn_trace_gettable(@path, DEFAULT) 
WHERE 
EventClass IN (92,93) 
ORDER BY 
StartTime DESC;

/*
Index Fragmentation
It is generally a good idea to choose ever-increasing fields as clustered keys. If, for any reason, a database doesn’t follow this pattern, index fragmentation will happen and you then need to check the fragmentation level of the indexes.
When a new record is inserted in the middle of existing records, a new page is allocated for the table and some records are moved from an existing page to the new page. This procedure is called page split and one of the consequences is that the table pages will not be sequentially organized inside the data file any more. In other words, the data pages of the table will be fragmented.
The DBA work round the problem by using configuration of the fill factor in the indexes that are subject to fragmentation. The fill factor determines the amount of the page that will be filled, leaving space for new records. The DBA has the task to manage the interval between the executions of the index maintenance in a way that index maintenance happens before the pages run out of free space for new records.
It’s the DBA’s task to balance the interval between the execution of indexes maintenances and the fill factor value. It’s important to check the fragmentation of the indexes to be sure that you achieved the correct balance between these values, and that fragmentation isn’t happening.
We can check the fragmentation of the indexes using the DMF sys.dm_db_index_physical_stats. This DMF can check information of a specific object or about all objects in a database. The first four parameters are the database id, table id, index id and partition id. The Table, index and partition parameters are optional.
The fifth parameter specifies how detailed the analysis should be. The options are ‘LIMITED’, ‘SAMPLED’ and ‘DETAILED’. The indexes are hierarchical, the fragmentation can happen in any level of the hierarchy. The most common and important fragmentation is in the leaf level and we can check the leaf level fragmentation using the ‘LIMITED’ option, which runs faster and with lower impact for the server.
We need to do a join with sys.indexes to get the name of the index and with sys.tables so we can use the field is_ms_shipped to exclude the system objects from the result. We also filter the result by the field index_type_desc looking only for clustered and nonclustered index, because this query would otherwise include heaps and xml indexes, and do some calculations in the predicate to exclude too small indexes, because these will always show some level of fragmentation.
The query to check the fragmentation in the leaf level of the indexes will be this:*/
	
	
SELECT object_name(IPS.object_id) AS [TableName], 
   SI.name AS [IndexName], 
   IPS.Index_type_desc, 
   IPS.avg_fragmentation_in_percent,    
   IPS.fragment_count, 
   IPS.avg_fragment_size_in_pages,
   alloc_unit_type_desc
FROM sys.dm_db_index_physical_stats(db_id(N'AdventureWorks2012'), NULL, NULL, NULL , 'LIMITED') IPS
   JOIN sys.tables ST WITH (nolock) ON IPS.object_id = ST.object_id
   JOIN sys.indexes SI WITH (nolock) ON IPS.object_id = SI.object_id AND IPS.index_id = SI.index_id
WHERE ST.is_ms_shipped = 0 and index_type_desc in ('NONCLUSTERED INDEX','CLUSTERED INDEX')
and  (fragment_count * avg_fragment_size_in_pages) > 20
ORDER BY avg_fragmentation_in_percent desc
We need a different query to check the fragmentation in other levels of the index. We need to use ‘Detailed’ mode instead of ‘Limited’ and we can exclude the information about the leaf level, since we already got this information using the ‘Limited’ mode.
The query to check the ‘Detailed’ fragmentation information will be this:
	SELECT object_name(IPS.object_id) AS [TableName], 
   SI.name AS [IndexName], 
   IPS.Index_type_desc, 
   IPS.avg_fragmentation_in_percent, 
   IPS.avg_page_space_used_in_percent, 
   IPS.record_count, 
   IPS.ghost_record_count,
   IPS.fragment_count, 
   IPS.avg_fragment_size_in_pages,
   alloc_unit_type_desc,
   index_level 
FROM sys.dm_db_index_physical_stats(db_id(N'AdventureWorks2012'), NULL, NULL, NULL , 'DETAILED') IPS
   JOIN sys.tables ST WITH (nolock) ON IPS.object_id = ST.object_id
   JOIN sys.indexes SI WITH (nolock) ON IPS.object_id = SI.object_id AND IPS.index_id = SI.index_id
WHERE ST.is_ms_shipped = 0  and (fragment_count * avg_fragment_size_in_pages) > 20
and index_type_desc in ('NONCLUSTERED INDEX','CLUSTERED INDEX') and index_level<>0
ORDER BY avg_fragmentation_in_percent desc



--Job Status
/*We often have several jobs defined in our SQL Servers and we need an easy way to check if any job has failed. Of course, we can check one by one, but a query to check if any of the jobs has failed can be very useful.
We will use two system tables from the MSDB database to retrieve the information about the jobs.
•	sysjobs: This table has the information about the jobs
•	sysjobhistory: This table has the information about all the executions of the jobs, but for each execution there is a row for each step of the job
•	sysjobactivity: This table has the information about the last execution of each job and the last step executed for each job. Remember that the last step executed may not be the last existing step in many cases, for example, if the job failed.
A good result to retrieve is the last execution of each job, with the status of every step of the job. This information is in sysjobhistorytable, but there is a problem: There isn’t a field to identify each execution. We can order the records by the job_id, run_date (desc) and run_time (desc), but we still need to get the records about the last execution. It will be a different number of records for each job, according to the last step executed.
The first step is a simple query to retrieve the last executed step for each job from sysjobactivity table. The query will be like this:
*/

select job_id,last_executed_step_id
 from msdb.dbo.sysjobactivity
 where last_executed_step_id is not null
For each job we retrieved with the query above, we need to retrieve the records about the steps of the job from sysjobhistory table. We can do this using Cross Apply in the query and using the field last_executed_step_id as a parameter for the Top expression in the query. The query to retrieve the details of the last execution of each job will be like this:
	with qry as
(select job_id,last_executed_step_id
 from msdb.dbo.sysjobactivity
 where last_executed_step_id is not null)
select 
   job_name, run_status,
   run_date, run_time,
   run_duration, step_name, message
 from qry
cross apply
(select top (qry.last_executed_step_id + 1)
        sysjobs.name as job_name,
        sysjobhistory.run_status,
        run_date, run_time,
        run_duration, step_name,
        message, step_id
             FROM   msdb.dbo.sysjobhistory
             INNER JOIN msdb.dbo.sysjobs
               ON msdb.dbo.sysjobhistory.job_id = msdb.dbo.sysjobs.job_id
    where msdb.dbo.sysjobs.job_id=qry.job_id
order by run_date desc,run_time desc) t
order by job_name,step_id
Finally, we need to translate the fields ‘ run_date ‘, ‘ run_time ‘ and ‘ run_status ‘ to a more readable format. Let’s use some functions to format these fields:
run_date:
	convert(date,convert(varchar,run_date)) run_date
run_time:
	      Isnull(Substring(CONVERT(VARCHAR, run_time + 1000000), 2, 2) + ':' +
         Substring(CONVERT(VARCHAR, run_time + 1000000), 4, 2)
       + ':' +
         Substring(CONVERT(VARCHAR, run_time + 1000000), 6, 2), '') as run_time
run_status:
	             CASE sysjobhistory.run_status
               WHEN 0 THEN 'Failed'
               WHEN 1 THEN 'Succeeded'
               WHEN 2 THEN 'Retry'
           WHEN 3 THEN 'Cancelled'
             END
             AS
             run_status
To make the use of this query easier, we can filter the result for only the failed executions and create a view for this query. The view will be like this:
	Create View LastFailedJobs as
with qry as
(select job_id,last_executed_step_id
 from msdb.dbo.sysjobactivity
 where last_executed_step_id is not null)
select 
   job_name, 
   CASE run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
    END
    AS
    run_status,
   convert(date,convert(varchar,run_date)) run_date, 
    Isnull(Substring(CONVERT(VARCHAR, run_time + 1000000), 2, 2) + ':' +
                Substring(CONVERT(VARCHAR, run_time + 1000000), 4, 2)
        + ':' +
        Substring(CONVERT(VARCHAR, run_time + 1000000), 6, 2), '') as run_time,
   run_duration, step_name, message
 from qry
cross apply
(select top (qry.last_executed_step_id + 1)
        sysjobs.name as job_name,
        sysjobhistory.run_status,
        run_date, run_time,
        run_duration, step_name,
        message, step_id
             FROM   msdb.dbo.sysjobhistory
             INNER JOIN msdb.dbo.sysjobs
               ON msdb.dbo.sysjobhistory.job_id = msdb.dbo.sysjobs.job_id
    where msdb.dbo.sysjobs.job_id=qry.job_id
order by run_date desc,run_time desc) t
where run_status<>1
order by job_name,step_id


/*Memory Use
Does our SQL Server has enough memory or our server is under memory pressure?
We need to check the buffer cache to identify if we have a good amount of cache hits and there isn’t memory pressure.
We can do this by checking performance counters. Three good performance counters to check are:
•	Page Life Expectancy: It’s Lifetime of the pages in the cache. The recommended value is over 300 sec.
•	Free List Stalls/sec: The number of requests that have to wait for a free page. If this value is high, your server is under memory pressure.
•	Page Reads/sec: If this counter has a high value this will confirm the memory pressure already highlighted by two counters
The query to retrieve these values will be like this:*/


SELECT object_name, counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE [object_name] LIKE '%Buffer Manager%'
AND [counter_name] in ('Page life expectancy','Free list stalls/sec',
'Page reads/sec')

/*
If you identify in the result that your server is under pressure, you have two ways to solve the problem:
•	Increase the server memory: You can add more memory or adjust the configuration ‘max server memory’ if possible.
•	Adjust the queries: You can optimize the queries of your applications, reducing the number of pages to read in each query and reducing the memory pressure.
*/

--1. query to show us the missing index in the order of the impact their creation will have:
SELECT TOP 20
ROUND(s.avg_total_user_cost *
       s.avg_user_impact
        * (s.user_seeks + s.user_scans),0)
                 AS [Total Cost]
,d.[statement] AS [Table Name]
,equality_columns
,inequality_columns
,included_columns
FROM sys.dm_db_missing_index_groups g
INNER JOIN sys.dm_db_missing_index_group_stats s
  ON s.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details d
  ON d.index_handle = g.index_handle
ORDER BY [Total Cost] DESC

--2. The query to find out the auto-growth that happened in our server is the following:
DECLARE @path NVARCHAR(260); 
 
SELECT 
@path = REVERSE(SUBSTRING(REVERSE([path]), 
CHARINDEX('\', REVERSE([path])), 260)) + N'log.trc' 
FROM sys.traces 
WHERE is_default = 1; 
 
SELECT 
DatabaseName, 
[FileName], 
SPID, 
Duration, 
StartTime, 
EndTime, 
FileType = CASE EventClass 
WHEN 92 THEN 'Data' 
WHEN 93 THEN 'Log' 
END 
FROM sys.fn_trace_gettable(@path, DEFAULT) 
WHERE 
EventClass IN (92,93) 
ORDER BY 
StartTime DESC;

--3. The query to check the fragmentation in the leaf level of the indexes will be this:
SELECT object_name(IPS.object_id) AS [TableName], 
   SI.name AS [IndexName], 
   IPS.Index_type_desc, 
   IPS.avg_fragmentation_in_percent,    
   IPS.fragment_count, 
   IPS.avg_fragment_size_in_pages,
   alloc_unit_type_desc
FROM sys.dm_db_index_physical_stats(db_id(N'AdventureWorks2012'), NULL, NULL, NULL , 'LIMITED') IPS
   JOIN sys.tables ST WITH (nolock) ON IPS.object_id = ST.object_id
   JOIN sys.indexes SI WITH (nolock) ON IPS.object_id = SI.object_id AND IPS.index_id = SI.index_id
WHERE ST.is_ms_shipped = 0 and index_type_desc in ('NONCLUSTERED INDEX','CLUSTERED INDEX')
and  (fragment_count * avg_fragment_size_in_pages) > 20
ORDER BY avg_fragmentation_in_percent desc


--4. The query to check the ‘Detailed’ fragmentation information will be this:
SELECT object_name(IPS.object_id) AS [TableName], 
   SI.name AS [IndexName], 
   IPS.Index_type_desc, 
   IPS.avg_fragmentation_in_percent, 
   IPS.avg_page_space_used_in_percent, 
   IPS.record_count, 
   IPS.ghost_record_count,
   IPS.fragment_count, 
   IPS.avg_fragment_size_in_pages,
   alloc_unit_type_desc,
   index_level 
FROM sys.dm_db_index_physical_stats(db_id(N'AdventureWorks2012'), NULL, NULL, NULL , 'DETAILED') IPS
   JOIN sys.tables ST WITH (nolock) ON IPS.object_id = ST.object_id
   JOIN sys.indexes SI WITH (nolock) ON IPS.object_id = SI.object_id AND IPS.index_id = SI.index_id
WHERE ST.is_ms_shipped = 0  and (fragment_count * avg_fragment_size_in_pages) > 20
and index_type_desc in ('NONCLUSTERED INDEX','CLUSTERED INDEX') and index_level<>0
ORDER BY avg_fragmentation_in_percent desc

--5. The query to retrieve the details of the last execution of each job will be like this:
with qry as
(select job_id,last_executed_step_id
from msdb.dbo.sysjobactivity
where last_executed_step_id is not null)
select 
   job_name, run_status,
   run_date, run_time,
   run_duration, step_name, message
from qry
cross apply
(select top (qry.last_executed_step_id + 1)
        sysjobs.name as job_name,
        sysjobhistory.run_status,
        run_date, run_time,
        run_duration, step_name,
        message, step_id
             FROM   msdb.dbo.sysjobhistory
             INNER JOIN msdb.dbo.sysjobs
               ON msdb.dbo.sysjobhistory.job_id = msdb.dbo.sysjobs.job_id
    where msdb.dbo.sysjobs.job_id=qry.job_id
order by run_date desc,run_time desc) t
order by job_name,step_id


--6.SIMILAR QUERY AS ABOVE
Create View LastFailedJobs as
with qry as
(select job_id,last_executed_step_id
from msdb.dbo.sysjobactivity
where last_executed_step_id is not null)
select 
   job_name, 
   CASE run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
    END
    AS
    run_status,
   convert(date,convert(varchar,run_date)) run_date, 
    Isnull(Substring(CONVERT(VARCHAR, run_time + 1000000), 2, 2) + ':' +
                Substring(CONVERT(VARCHAR, run_time + 1000000), 4, 2)
        + ':' +
        Substring(CONVERT(VARCHAR, run_time + 1000000), 6, 2), '') as run_time,
   run_duration, step_name, message
from qry
cross apply
(select top (qry.last_executed_step_id + 1)
        sysjobs.name as job_name,
        sysjobhistory.run_status,
        run_date, run_time,
        run_duration, step_name,
        message, step_id
             FROM   msdb.dbo.sysjobhistory
             INNER JOIN msdb.dbo.sysjobs
               ON msdb.dbo.sysjobhistory.job_id = msdb.dbo.sysjobs.job_id
    where msdb.dbo.sysjobs.job_id=qry.job_id
order by run_date desc,run_time desc) t
where run_status<>1
order by job_name,step_id


--7. Finding the blocking statement in Sql Server
SELECT
db.name DBName,
tl.request_session_id,
wt.blocking_session_id,
OBJECT_NAME(p.OBJECT_ID) BlockedObjectName,
tl.resource_type,
h1.TEXT AS RequestingText,
h2.TEXT AS BlockingTest,
tl.request_mode
FROM sys.dm_tran_locks AS tl
INNER JOIN sys.databases db ON db.database_id = tl.resource_database_id
INNER JOIN sys.dm_os_waiting_tasks AS wt ON tl.lock_owner_address = wt.resource_address
INNER JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id
INNER JOIN sys.dm_exec_connections ec1 ON ec1.session_id = tl.request_session_id
INNER JOIN sys.dm_exec_connections ec2 ON ec2.session_id = wt.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(ec1.most_recent_sql_handle) AS h1
CROSS APPLY sys.dm_exec_sql_text(ec2.most_recent_sql_handle) AS h2
GO

--8. Finding the user who running the query in the server
SELECT
s.session_id AS SessionID,
 s.login_time AS LoginTime,
 s.[host_name] AS HostName,
 s.[program_name] AS ProgramName,
 s.login_name AS LoginName,
 s.[status] AS SessionStatus,
 st.text AS SQLText,
 (s.cpu_time / 1000) AS CPUTimeInSec,
 (s.memory_usage * 8) AS MemoryUsageKB,
 (CAST(s.total_scheduled_time AS FLOAT) / 1000) AS TotalScheduledTimeInSec,
 (CAST(s.total_elapsed_time AS FLOAT) / 1000) AS ElapsedTimeInSec,
 s.reads AS ReadsThisSession,
 s.writes AS WritesThisSession,
 s.logical_reads AS LogicalReads,
 CASE s.transaction_isolation_level
 WHEN 0 THEN 'Unspecified'
 WHEN 1 THEN 'ReadUncommitted'
 WHEN 2 THEN 'ReadCommitted'
 WHEN 3 THEN 'Repeatable'
 WHEN 4 THEN 'Serializable'
 WHEN 5 THEN 'Snapshot'
 END AS TransactionIsolationLevel,
 s.row_count AS RowsReturnedSoFar,
 c.net_transport AS ConnectionProtocol,
 c.num_reads AS PacketReadsThisConnection,
 c.num_writes AS PacketWritesThisConnection,
 c.client_net_address AS RemoteHostIP,
 c.local_net_address AS LocalConnectionIP
 FROM sys.dm_exec_sessions s INNER JOIN sys.dm_exec_connections c
 ON s.session_id = c.session_id
 CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS st
 WHERE s.is_user_process = 1 and [status]='running'
 ORDER BY ElapsedTimeInSec,LoginTime DESC

--9. LAST BACK UP Timings
SELECT db.name,
case when MAX(b.backup_finish_date) is NULL then 'No Backup' elseconvert(varchar(100),
MAX(b.backup_finish_date)) end AS last_backup_finish_date
FROM sys.databases db LEFT OUTER JOIN msdb.dbo.backupset b ON db.name =b.database_name AND b.type = 'D'  WHERE db.database_id NOT IN (2)  GROUP BYdb.name ORDER BY 2 DESC

--10.PATH WHERE THE BACKUP HAVE BEEN SAVED
SELECT Distinct physical_device_name FROM msdb.dbo.backupmediafamily

--11. Query which has taken more time for executing
SELECT TOP 10 obj.name, max_logical_reads, max_elapsed_time
FROM sys.dm_exec_query_stats a
CROSS APPLY sys.dm_exec_sql_text(sql_handle) hnd
INNER JOIN sys.sysobjects obj on hnd.objectid = obj.id

ORDER BY max_logical_reads DESC

--12. List expensive queries
DECLARE @MinExecutions int;
SET @MinExecutions = 5

SELECT EQS.total_worker_time AS TotalWorkerTime
      ,EQS.total_logical_reads + EQS.total_logical_writes AS TotalLogicalIO
      ,EQS.execution_count As ExeCnt
      ,EQS.last_execution_time AS LastUsage
      ,EQS.total_worker_time / EQS.execution_count as AvgCPUTimeMiS
      ,(EQS.total_logical_reads + EQS.total_logical_writes) / EQS.execution_count 
       AS AvgLogicalIO
      ,DB.name AS DatabaseName
      ,SUBSTRING(EST.text
                ,1 + EQS.statement_start_offset / 2
                ,(CASE WHEN EQS.statement_end_offset = -1 
                       THEN LEN(convert(nvarchar(max), EST.text)) * 2 
                       ELSE EQS.statement_end_offset END 
                 - EQS.statement_start_offset) / 2
                ) AS SqlStatement
      -- Optional with Query plan; remove comment to show, but then the query takes !!much longer time!!
      --,EQP.[query_plan] AS [QueryPlan]
FROM sys.dm_exec_query_stats AS EQS
     CROSS APPLY sys.dm_exec_sql_text(EQS.sql_handle) AS EST
     CROSS APPLY sys.dm_exec_query_plan(EQS.plan_handle) AS EQP
     LEFT JOIN sys.databases AS DB
         ON EST.dbid = DB.database_id     
WHERE EQS.execution_count > @MinExecutions
      AND EQS.last_execution_time > DATEDIFF(MONTH, -1, GETDATE())
ORDER BY AvgLogicalIo DESC
        ,AvgCPUTimeMiS DESC


--DBCC COMMANDS

--1.DBCC CHECKALLOC checks page usage and allocation in the database. Use this command if allocation errors are found for the database. If you run DBCC CHECKDB, you do not need to run DBCC CHECKALLOC, as DBCC CHECKDB includes the same checks (and more) that DBCC CHECKALLOC performs. 
DBCC CHECKALLOC

--2.This command checks for consistency in and between system tables. This command is not executed within the DBCC CHECKDB command, so running this command weekly is recommended.
DBCC CHECKCATALOG

--3.DBCC CHECKCONSTRAINTS alerts you to any CHECK or constraint violations. Use it if you suspect that there are rows in your tables that do not meet the constraint or CHECK constraint rules.
DBCC CHECKCONSTRAINTS

--4.A very important DBCC command, DBCC CHECKDB should run on your SQL Server instance on at least a weekly basis. Although each release of SQL Server reduces occurrences of integrity or allocation errors, they still do happen. DBCC CHECKDB includes the same checks as DBCC CHECKALLOC and DBCC CHECKTABLE. DBCC CHECKDB can be rough on concurrency, so be sure to run it at off-peak times.
DBCC CHECKDB

--5.DBCC CHECKTABLE is almost identical to DBCC CHECKDB, except that it is performed at the table level, not the database level. DBCC CHECKTABLE verifies index and data page links, index sort order, page pointers, index pointers, data page integrity, and page offsets. DBCC CHECKTABLE uses schema locks by default, but can use the TABLOCK option to acquire a shared table lock. CHECKTABLE also performs object checking using parallelism by default (if on a multi-CPU system).
DBCC CHECKTABLE

--6.DBCC CHECKFILEGROUP works just like DBCC CHECKDB, only DBCC CHECKFILEGROUP checks the specified filegroup for allocation and structural issues. If you have a very large database (this term is relative, and higher end systems may be more apt at performing well with multi-GB or TB systems ) , running DBCC CHECKDB may be time-prohibitive. If your database is divided into user defined filegroups, DBCC CHECKFILEGROUP will allow you to isolate your integrity checks, as well as stagger them over time.
DBCC CHECKFILEGROUP

--7.DBCC CHECKIDENT returns the current identity value for the specified table, and allows you to correct the identity value if necessary.
DBCC CHECKIDENT

--8.If your database allows modifications and has indexes, you should rebuild your indexes on a regular basis. The frequency of your index rebuilds depends on the level of database activity, and how quickly your database and indexes become fragmented. DBCC DBREINDEX allows you to rebuild one or all indexes for a table. Like DBCC CHECKDB, DBCC CHECKTABLE, DBCC CHECKALLOC, running DBREINDEX during peak activity times can significantly reduce concurrency.
DBCC DBREINDEX

--9.Microsoft introduced the excellent DBCC INDEXDEFRAG statement beginning with SQL Server 2000. This DBCC command, unlike DBCC DBREINDEX, does not hold long term locks on indexes. Use DBCC INDEXDEFRAG for indexes that are not very fragmented, otherwise the time this operation takes will be far longer then running DBCC DBREINDEX. In spite of it's ability to run during peak periods, DBCC INDEXDEFRAG has had limited effectiveness compared to DBCC DBREINDEX (or drop/create index).
DBCC INDEXDEFRAG

--10.The DBCC INPUTBUFFER command is used to view the last statement sent by the client connection to SQL Server. When calling this DBCC command, you designate the SPID to examine. (SPID is the process ID, which you can get from viewing current activity in Enterprise Manager or executing sp_who. )
DBCC INPUTBUFFER

--11.DBCC OPENTRAN is a Transact-SQL command that is used to view the oldest running transaction for the selected database. The DBCC command is very useful for troubleshooting orphaned connections (connections still open on the database but disconnected from the application or client), and identification of transactions missing a COMMIT or ROLLBACK. This command also returns the oldest distributed and undistributed replicated transactions, if any exist within the database. If there are no active transactions, no data will be returned. If you are having issues with your transaction log not truncating inactive portions, DBCC OPENTRAN can show if an open transaction may be causing it.
DBCC OPENTRAN

--12.You may not use this too frequently, however it is an interesting DBCC command to execute periodically, particularly when you suspect you have memory issues. DBCC PROCCACHE provides information about the size and usage of the SQL Server procedure cache.
DBCC PROCCACHE

--13.The DBCC SHOWCONTIG command reveals the level of fragmentation for a specific table and its indices. This DBCC command is critical to determining if your table or index has internal or external fragmentation. Internal fragmentation concerns how full an 8K page is. When a page is underutilized, more I/O operations may be necessary to fulfill a query request than if the page was full, or almost full. External fragmentation concerns how contiguous the extents are. There are eight 8K pages per extent, making each extent 64K. Several extents can make up the data of a table or index. If the extents are not physically close to each other, and are not in order, performance could diminish.
DBCC SHOWCONTIG

--14.DBCC SHRINKDATABASE shrinks the data and log files in your database. Avoid executing this command during busy periods in production, as it has a negative impact on I/O and user concurrency. Also remember that you cannot shrink a database past the target percentage specified, shrink smaller than the model database, shrink a file past the original file creation size, or shrink a file size used in an ALTER DATABASE statement.
DBCC SHRINKDATABASE

--15.DBCC SHRINKFILE allows you to shrink the size of individual data and log files. (Use sp_helpfile to gather database file ids and sizes).
DBCC SHRINKFILE

--16. Trace flags are used within SQL Server to temporarily enable or disable specific SQL Server instance characteristics. Traces are enabled using the DBCC TRACEON command, and disabled using DBCC TRACEOFF. DBCC TRACESTATUS is used to displays the status of trace flags. You'll most often see TRACEON used in conjunction with deadlock logging (providing more verbose error information).
DBCC TRACEOFF, TRACEON, TRACESTATUS

--17.Execute DBCC USEROPTIONS to see what user options are in effect for your specific user connection. This can be helpful if you are trying to determine if you current user options are inconsistent with the database options. 
DBCC USEROPTIONS

