--1.USERS

SELECT  *
FROM    sys.sysusers s
WHERE   ISNUMERIC(name) = 1;

--3.USERS WHO HAVE SESSIONS

SELECT  s.session_id ,
        s.login_time ,
        s.host_name ,
        s.program_name ,
        s.client_interface_name ,
        s.total_elapsed_time ,
        s.open_transaction_count
FROM    sys.dm_exec_sessions s 


--4.RUNNING PROCESSES 

SELECT  S.login_name ,
        S.session_id ,
        DB_NAME(R.database_id) AS db ,
        S.program_name ,
        s2.text
FROM    sys.dm_exec_sessions S
        INNER JOIN sys.dm_exec_requests R ON S.session_id = R.session_id
        CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) AS s2
WHERE   S.is_user_process = 1;



--5.HEAP TABLES

SELECT  SCHEMA_NAME(t.schema_id) AS SchemaName ,
        t.name AS TableName ,
        ( SELECT    SUM(row_count)
          FROM      sys.dm_db_partition_stats
          WHERE     object_id = t.object_id
                    AND index_id IN ( 0, 1 )
        ) AS TableRowCount ,
        ( SELECT    COUNT(1)
          FROM      sys.indexes i
          WHERE     i.object_id = t.object_id
                    AND index_id > 1
        ) AS NonClusterIndexCount
FROM    sys.tables t
WHERE   OBJECTPROPERTY(t.object_id, 'TableHasClustIndex') = 0;


--6.HEAP TABLES WHICH HAVE IDENTITY COLUMNS

CREATE TABLE #tmp1
    (
      DBName sysname ,
      object_id INT ,
      SchemaName sysname ,
      TableName sysname ,
      TableRowCount INT ,
      NonClusterIndexCount INT ,
      IdentityColumn sysname ,
      PrimaryKeyCreateScript VARCHAR(MAX)
    );
EXEC sp_MSforeachdb '  use ?;  insert #tmp1  Select *  	,  ''  use ?;   ALTER TABLE [''+SchemaName+''].[''+TableName+''] ADD  CONSTRAINT [PK_''+TableName+''_''+IdentityColumn+''] PRIMARY KEY CLUSTERED   (  	[''+IdentityColumn+''] ASC  )WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = ON, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]  '' as PrimaryKeyCreateScript  from (  select DB_NAME() as DBName,t.object_id,schema_name(t.schema_id) as SchemaName,t.name as TableName      ,(select sum(row_count) from sys.dm_db_partition_stats where object_id=t.object_id and index_id in (0,1)) as TableRowCount       ,(Select count(1) from sys.indexes i where i.object_id=t.object_id and index_id>1) as NonClusterIndexCount  	,(Select name from sys.columns c where c.object_id=t.object_id and is_identity=1) as IdentityColumn		  from sys.tables t  where objectproperty(t.object_id,''TableHasClustIndex'')=0  	and objectproperty(t.object_id,''TableHasIdentity'')=1  	and objectproperty(t.object_id,''TableHasPrimaryKey'')=0  ) tbl1	  ';
SELECT  *
FROM    #tmp1
WHERE   DBName NOT IN ( 'master', 'model', 'msdb', 'tempdb' )
ORDER BY DBName

--7.ALL INDEXES

SELECT  OBJECT_NAME(object_id) AS objectName ,
        object_id ,
        name ,
        index_id ,
        type ,
        type_desc ,
        is_unique
FROM    sys.indexes
WHERE   object_id > 100;

--8.INDEXSIZE- FILLFACTOR

SELECT  SCHEMA_NAME(o.schema_id) sch_name ,
        o.name table_name ,
        i.name index_name ,
        i.index_id ,
        i.type_desc index_type ,
        ps.used_page_count * 8 / 1024 size_mb ,
        ps.row_count ,
        ps.used_page_count ,
        i.fill_factor ,
        i.is_padded ,
        i.allow_row_locks ,
        i.allow_page_locks ,
        'ALTER INDEX [' + i.name + '] ON [' + SCHEMA_NAME(o.schema_id) + '].['
        + o.name + '] ' + CHAR(13) + 'REBUILD WITH (ALLOW_ROW_LOCKS = '
        + IIF(i.allow_row_locks = 1, 'ON', 'OFF') + ', ALLOW_PAGE_LOCKS = '
        + IIF(i.allow_page_locks = 1, 'ON', 'OFF') + ', ' + CHAR(13)
        + 'FILLFACTOR = ' + CONVERT(VARCHAR(3), i.fill_factor)
        + ', PAD_INDEX = ' + IIF(i.is_padded = 1, 'ON', 'OFF') + ', '
        + CHAR(13) + 'SORT_IN_TEMPDB = ON, ONLINE = ON, MAXDOP = 10);'
        + CHAR(13) + CHAR(10) + 'GO' + CHAR(13) + CHAR(10)
FROM    sys.indexes i
        JOIN sys.objects o ON o.object_id = i.object_id
        JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id
                                             AND i.index_id = ps.index_id
WHERE   o.is_ms_shipped = 0
        AND i.index_id > 0;   --AND o.name LIKE '%ana_kım%' --HEAPler haric    ORDER BY o.name, i.index_id

--9.INDEXFRAG

SELECT TOP 100
        DB_NAME() ,
        o.name table_name ,
        i.name index_name ,
        i.type_desc index_type ,
        ps.partition_number ,
        ps.alloc_unit_type_desc ,
        ps.avg_fragmentation_in_percent ,
        ps.fragment_count ,
        ps.page_count
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'limited') ps
        JOIN sys.objects o ON o.object_id = ps.object_id
        JOIN sys.indexes i ON i.object_id = ps.object_id
                              AND i.index_id = ps.index_id
WHERE   o.is_ms_shipped = 0
        AND ps.page_count > 1000
        AND ps.avg_fragmentation_in_percent > 5
ORDER BY ps.avg_fragmentation_in_percent DESC;

--10.UNUSEDINDEXES

SELECT  SCH.name + '.' + OBJ.name AS ObjectName ,
        OBJ.type_desc AS ObjectType ,
        IDX.name AS IndexName ,
        IDX.type_desc AS IndexType
FROM    sys.indexes AS IDX
        LEFT JOIN sys.dm_db_index_usage_stats AS IUS ON IUS.index_id = IDX.index_id
                                                        AND IUS.object_id = IDX.object_id
        INNER JOIN sys.objects AS OBJ ON IDX.object_id = OBJ.object_id
        INNER JOIN sys.schemas AS SCH ON OBJ.schema_id = SCH.schema_id
WHERE   OBJ.is_ms_shipped = 0       -- Exclude MS objects        
AND OBJ.type IN ('U', 'V')  -- Only user defined tables & views        
AND IDX.type > 0            -- Ignore heaps        
AND IDX.is_disabled = 0     -- Disabled indexes aren't used anyway        
AND IDX.is_primary_key = 0  -- Exclude PK => FK constraints / part of business logic        
AND IDX.is_unique = 0       -- Exclude unique indexes => part of business logic        
AND IUS.object_id IS NULL  
ORDER BY ObjectName ,IndexName;


--11.INDEXUSAGE

WITH    CTE ( dbname, tablename, indexname, indextype, indexusage, filegroupname, MB, cols, included, user_hits, user_seeks, user_scans, user_lookups, user_updates, stats_date )
          AS ( SELECT   DB_NAME(a.database_id) ,
                        OBJECT_NAME(a.object_id) "tablename" ,
                        c.name "indexname" ,
                        c.type_desc "indextype" ,
                        CASE c.is_unique
                          WHEN 1 THEN CASE is_primary_key
                                        WHEN 1 THEN 'Primary Key'
                                        ELSE 'Unique'
                                      END
                          ELSE CASE c.is_unique_constraint
                                 WHEN 1 THEN 'Unique Constraint'
                                 ELSE 'Performance'
                               END
                        END "IndexUsage" ,
                        FILEGROUP_NAME(c.data_space_id) "FileGroupName" ,
                        ( SELECT    CEILING(used / 128)
                          FROM      sysindexes b
                          WHERE     b.name = c.name
                                    AND c.index_id = b.indid
                                    AND b.[id] = c.[object_id]
                        ) "MB" ,
                        ( SELECT    COUNT(*)
                          FROM      sys.index_columns d
                          WHERE     a.object_id = d.object_id
                                    AND a.index_id = d.index_id
                                    AND d.is_included_column = 0
                        ) "cols" ,
                        ( SELECT    COUNT(*)
                          FROM      sys.index_columns d
                          WHERE     a.object_id = d.object_id
                                    AND a.index_id = d.index_id
                                    AND d.is_included_column = 1
                        ) "included" ,
                        ( a.user_seeks + a.user_scans + a.user_lookups ) "user_hits" ,
                        a.user_seeks ,
                        a.user_scans ,
                        a.user_lookups ,
                        a.user_updates ,
                        a.last_user_update "stats_date"
               FROM     sys.dm_db_index_usage_stats a
                        JOIN sys.indexes AS c ON a.object_id = c.object_id
                                                 AND a.index_id = c.index_id
               WHERE    a.object_id > 1000 
														         			  					  				-- exclude system tables  		
                        AND c.type <> 0  
																												-- exclude HEAPs  	
                        AND c.is_disabled = 0
																												-- only active indexes  		
                        AND a.database_id = DB_ID()
																												-- for current database only
             )
    SELECT  dbname ,
            tablename ,
            indexname ,
            indextype ,
            indexusage ,
            filegroupname ,
            MB ,
            cols ,
            included ,
            ROUND(CAST(user_seeks AS REAL) / COALESCE(NULLIF(user_hits, 0), 1)
                  * 100, 0) AS "perc_seeks" ,
            ROUND(CAST(user_scans AS REAL) / COALESCE(NULLIF(user_hits, 0), 1)
                  * 100, 0) AS "perc_scans" ,
            ROUND(CAST(user_lookups AS REAL) / COALESCE(NULLIF(user_hits, 0),
                                                        1) * 100, 0) AS "perc_lookups" ,
            user_hits ,
            user_updates ,
            CASE WHEN user_hits = 0 THEN -user_updates
                 ELSE ROUND(CAST(user_seeks + user_scans * .8 + user_lookups
                            * 1.2 AS REAL)
                            / CAST(COALESCE(NULLIF(user_updates, 0), 1) AS REAL),
                            4)
            END "ratio" ,
            ( user_updates - user_hits ) / COALESCE(NULLIF(MB, 0), 1) AS "pressure" ,
            stats_date
    FROM    CTE
    WHERE   MB <> 0;


--12.MISSING INDEX

SELECT  d.statement ,
        d.equality_columns ,
        d.inequality_columns ,
        d.included_columns ,
        s.avg_total_user_cost ,
        s.avg_user_impact ,
        s.user_seeks ,
        s.user_scans ,
        priority = avg_total_user_cost * avg_user_impact * ( user_seeks
                                                             + user_scans )
FROM    sys.dm_db_missing_index_group_stats s
        JOIN sys.dm_db_missing_index_groups g ON s.group_handle = g.index_group_handle
        JOIN sys.dm_db_missing_index_details d ON g.index_handle = d.index_handle
ORDER BY priority DESC;

--13.ANY BLOCKING

SELECT  s2.text ,
        *
FROM    sys.dm_exec_sessions S
        INNER JOIN sys.dm_exec_requests R ON S.session_id = R.session_id
        CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) AS s2
WHERE   S.is_user_process = 1
        AND R.blocking_session_id > 0

--EXPENSIVE QUERIES

SELECT TOP 200
        COALESCE(DB_NAME(st.dbid), DB_NAME(CONVERT (INT, pa.value)), 'Empty') AS DBName ,
        SUBSTRING(st.text, ( qs.statement_start_offset / 2 ) + 1,
                  ( ( CASE qs.statement_end_offset
                        WHEN -1 THEN DATALENGTH(st.text)
                        ELSE qs.statement_end_offset
                      END - qs.statement_start_offset ) / 2 ) + 1) AS StatementText ,
        qs.plan_generation_num AS PlanGenerationNumber ,
        qs.execution_count AS ExecutionCount ,
        ( qs.total_worker_time / 1000 ) AS CPUTimeTotal ,
        ( ( qs.total_worker_time / 1000 ) / qs.execution_count ) AS CPUTimeAvg ,
        ( qs.total_elapsed_time / 1000 ) AS DurationTimeTotal ,
        ( ( qs.total_elapsed_time / 1000 ) / qs.execution_count ) AS DurationTimeAvg ,
        qs.total_physical_reads AS PhysicalReadsTotal ,
        ( qs.total_physical_reads / qs.execution_count ) AS PhysicalReadsAvg ,
        qs.total_logical_reads AS LogicalReadsTotal ,
        ( qs.total_logical_reads / qs.execution_count ) AS LogicalReadsAvg ,
        qs.last_execution_time AS LastExecutionTime ,
        st.text AS ProcedureTextOrBatchText
FROM    sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(plan_handle) qp
        CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
WHERE   attribute = 'dbid'
        AND qs.execution_count > 1000
ORDER BY LogicalReadsAvg DESC;  
--ORDER BY ((qs.total_worker_time/1000)+(qs.total_elapsed_time/1000)+qs.total_logical_reads) desc  
--order by CPUTimeTotal desc  
--order by CPUTimeAvg desc  
--order by DurationTimeTotal desc  
--order by DurationTimeAvg desc  
--order by PhysicalReadsTotal desc  
--order by PhysicalReadsAvg desc  
--order by LogicalReadsTotal desc

--15.EVPENSIVE QUERIES_2

SELECT  S2.text ,
        a.execution_count
FROM    sys.dm_exec_query_stats a
        CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS S2
WHERE   a.query_hash IN (
        SELECT  query_hash
        FROM    sys.dm_exec_cached_plans a
                INNER JOIN sys.dm_exec_query_stats b ON a.plan_handle = b.plan_handle
        GROUP BY query_hash )
ORDER BY a.execution_count DESC;

--16.OBJECTS WHICH INCLUDE "xxxxxxx" IN ITS T-SQL SCRIPT

SELECT  O.name ,
        O.type ,
        O1.name AS parent_object
FROM    syscomments C
        INNER JOIN sysobjects O ON O.id = C.id
        LEFT JOIN sysobjects O1 ON O1.id = O.parent_obj
        LEFT JOIN sys.procedures SP ON SP.object_id = O.id
        LEFT JOIN sys.triggers TR ON TR.object_id = O.id
        LEFT JOIN sys.views VW ON VW.object_id = O.id
WHERE   text LIKE '%xxxxxx%'
        AND ( ( DATEADD(DAY, 7, SP.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, SP.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.modify_date) <= GETDATE() )
            )
UNION
SELECT  O.name ,
        O.type ,
        O1.name AS parent_object
FROM    syscomments C
        INNER JOIN sysobjects O ON O.id = C.id
        LEFT JOIN sysobjects O1 ON O1.id = O.parent_obj
        LEFT JOIN sys.procedures SP ON SP.object_id = O.id
        LEFT JOIN sys.triggers TR ON TR.object_id = O.id
        LEFT JOIN sys.views VW ON VW.object_id = O.id
WHERE   text LIKE '%xxxxxxx%'
        AND ( ( DATEADD(DAY, 7, SP.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, SP.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.modify_date) <= GETDATE() )
            )
UNION
SELECT  O.name ,
        O.type ,
        O1.name AS parent_object
FROM    syscomments C
        INNER JOIN sysobjects O ON O.id = C.id
        LEFT JOIN sysobjects O1 ON O1.id = O.parent_obj
        LEFT JOIN sys.procedures SP ON SP.object_id = O.id
        LEFT JOIN sys.triggers TR ON TR.object_id = O.id
        LEFT JOIN sys.views VW ON VW.object_id = O.id
WHERE   text LIKE '%xxxxxxxxx%'
        AND ( ( DATEADD(DAY, 7, SP.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, SP.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.modify_date) <= GETDATE() )
            )
UNION
SELECT  O.name ,
        O.type ,
        O1.name AS parent_object
FROM    syscomments C
        INNER JOIN sysobjects O ON O.id = C.id
        LEFT JOIN sysobjects O1 ON O1.id = O.parent_obj
        LEFT JOIN sys.procedures SP ON SP.object_id = O.id
        LEFT JOIN sys.triggers TR ON TR.object_id = O.id
        LEFT JOIN sys.views VW ON VW.object_id = O.id
WHERE   text LIKE '%xxxxxxxx%'
        AND ( ( DATEADD(DAY, 7, SP.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, SP.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, TR.modify_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.create_date) <= GETDATE() )
              OR ( DATEADD(DAY, 7, VW.modify_date) <= GETDATE() )
            );

--18.DISABLED TRIGGERS

SELECT  SO1.name AS TRIGGERNAME ,
        CASE OBJECTPROPERTY(OBJECT_ID(SO1.name), 'EXECISTRIGGERDISABLED')
          WHEN 0 THEN 'ENABLED'
          ELSE 'DISABLED'
        END AS STATUS ,
        SO2.name AS TABLENAME
FROM    sysobjects SO1
        JOIN sysobjects SO2 ON SO2.id = SO1.parent_obj
WHERE   SO1.type = 'TR'
        AND OBJECTPROPERTY(OBJECT_ID(SO1.name), 'EXECISTRIGGERDISABLED') <> 0;


--20.DB CPU USAGE

WITH    DB_CPU_Stats
          AS ( SELECT   DatabaseID ,
                        DB_NAME(DatabaseID) AS [DatabaseName] ,
                        SUM(total_worker_time) AS [CPU_Time_Ms]
               FROM     sys.dm_exec_query_stats AS qs
                        CROSS APPLY ( SELECT    CONVERT(INT, value) AS [DatabaseID]
                                      FROM      sys.dm_exec_plan_attributes(qs.plan_handle)
                                      WHERE     attribute = N'dbid'
                                    ) AS F_DB
               GROUP BY DatabaseID
             )
    SELECT  ROW_NUMBER() OVER ( ORDER BY [CPU_Time_Ms] DESC ) AS [row_num] ,
            DatabaseName ,
            [CPU_Time_Ms] ,
            CAST([CPU_Time_Ms] * 1.0 / SUM([CPU_Time_Ms]) OVER ( ) * 100.0 AS DECIMAL(5,
                                                              2)) AS [CPUPercent]
    FROM    DB_CPU_Stats
    WHERE   DatabaseID > 4 -- system databases              
            AND DatabaseID <> 32767 -- ResourceDB  
    ORDER BY row_num
OPTION  ( RECOMPILE );

--21.DEPENDENCY OBJECTS

EXEC sys.sp_depends @objname = N'SPXXXXXXXXX'

