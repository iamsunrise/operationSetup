create or replace procedure route_inspection is
begin
  --数据库状态
    select v$instance.STATUS,
    v$instance.INSTANCE_NAME,
    To_Char(v$instance.STARTUP_TIME, 'yyyymmdd hh24:mi:ss'),
    v$instance.HOST_NAME
    From v$instance;



  --检查控制文件状态和日志文件情况
  select * from v$controlfile;
  select * from v$log;
  select * from v$logfile;
  select * from v$sysstat;
  select * from v$session_longops;

  --检查状态不是“online”的数据文件，查询没有任何结果返回，代表当前所有数据文件都正常，否则 通知DBA作进一步检查，以做处理和恢复。
  SELECT '文件:' || file_name, status, TO_CHAR (file_id) AS fid
    FROM dba_data_files
   WHERE status <> 'AVAILABLE'
  UNION
  SELECT '表空间:' || tablespace_name, status, ''
    FROM dba_tablespaces
   WHERE status <> 'ONLINE'
  UNION
  SELECT '文件:' || filename, status, ''
    FROM v$recovery_file_status
  UNION
  SELECT (SELECT '文件:' || file_name
            FROM dba_data_files
           WHERE file_id = v1.file#) AS filename,
         DECODE (status, 'ACTIVE', '正处于备份状态', status),
         TO_CHAR (file#) AS fid
    FROM v$backup v1
   WHERE status <> 'NOT ACTIVE'
  UNION
  SELECT (SELECT '文件:' || NAME
            FROM v$datafile
           WHERE file# = t.file#), online_status, TO_CHAR (t.file#)
    FROM v$recover_file t;
   
  --数据缓冲区命中率（小于90%,则应该调整应用可可以考虑是否增大数据缓冲区）
  select round((sum(decode(name, 'consistent gets', value, 0)) +
               sum(decode(name, 'db block gets', value, 0)) -
               sum(decode(name, 'physical reads', value, 0))) /
               (sum(decode(name, 'consistent gets', value, 0)) +
               sum(decode(name, 'db block gets', value, 0))) * 100,
               2)
  --,sum(decode(NAME, 'consistent gets',VALUE, 0)),
  -- sum(decode(NAME, 'db block gets',VALUE, 0)),
  -- sum(decode(NAME, 'physical reads',VALUE, 0))
    from v$sysstat;

  --数据字典缓冲区命中率（低于90的命中率就算比较低的，需通知DBA进一步分析性能数据）
  select   round((1 - (sum(GETMISSES) / sum(GETS))) * 100,2)
           --,sum(GETS),sum(GETMISSES)         
  from     v$rowcache;

  --LIBRARYCACHE命中率（通常在98%以上，否则，需要要考虑加大共享池，绑定变量，修改cursor_sharing等参数。）
  select  round((sum(PINS) / (sum(PINS) + sum(RELOADS))) * 100,3)
          --,sum(PINS),
          -- sum(PINHITS),
          -- round((sum(PINHITS) / sum(PINS)) * 100,3),
          -- sum(RELOADS)
  from    v$librarycache;

  --检测使用率大于80%的表空间
  SELECT to_char(100 * sum_free_m / sum_m, '99.999') || '% ' AS pct_free,
         sum_free_m,
         sum_m,
         tablespace_name
    FROM (SELECT tablespace_name, sum(bytes) / 1024 / 1024 AS sum_m
            FROM dba_data_files
           GROUP BY tablespace_name),
         (SELECT tablespace_name AS fs_ts_name,
                 sum(bytes / 1024 / 1024) AS sum_free_m
            FROM dba_free_space
           GROUP BY tablespace_name)
   WHERE tablespace_name = fs_ts_name
     and 100 * sum_free_m / sum_m < 21
   order by pct_free;
   
   --检查Job是否正常(正常情况下，数据库 的job broken列应当为’N’ ，failures 为0)
   select job,
         broken,
         failures,
         substr(what, 1, 30) as what,
         log_user,
         last_date,
         last_sec,
         next_date,
         next_sec
    from dba_jobs;
    
    --当前数据库中表和索引最大可能的数据量
    select sum(bytes)/1024/1024 ||'M' from dba_segments;
    
   /*所有用户名和是否锁定(status 列 为 open的 是当前允许登录的用户
  除sys用户之外的其他所有用户的DEFAULT_TABLESPACE不应当是system表空间
  除sys用户之外的其他所有用户的TEMPORARY _TABLESPACE不应当是system表空间
  为保证安全，建议不再使用的用户应当将其锁定
  )*/
   select ACCOUNT_STATUS, username, DEFAULT_TABLESPACE, TEMPORARY_TABLESPACE
    from dba_users
   order by 1;
   
   /*具有dba权限的用户名为保证安全，建议 不授予sys用户以外的其他用户dba角色，
  如查询出结果，建议和应用人员联系，授予其所需要的权利，在不影响用户的工作的前提下，收回此用户的dba角色
  */
   
   select grantee,granted_role  from dba_role_privs t
  where t.granted_role  in ('DBA') and grantee <>'SYS'
  order by 2;


  --当前用户的所有角色
  select * from dba_role_privs t where t.grantee not in ('DBA','SYS') and t.grantee not in (select role from dba_roles);
    /*当前用户使用空间的信息*/
select rownum,t.* from (select owner,sum(bytes)/1024/1024  as bytes_in_M  from dba_segments group by owner order by 2 desc) t;


  --使用表空间大小的汇总
  --select rownum ,t.* from 
  --(select owner  ,sum(bytes)/1024/1024  as bytes_in_M ,tablespace_name from dba_segments 
  --group by owner ,tablespace_name order by 1   ) t;

  --所有的明细
  --select rownum ,t.* from 
  --(select owner  ,sum(bytes)/1024/1024 ||'M' as bytes_in_M ,nvl(segment_type,'               '||owner||' all objects size') from dba_segments 
  --group by rollup(owner,segment_type ) order by owner ) t;

  --表空间扩展信息
  SELECT TABLESPACE_NAME,INITIAL_EXTENT,NEXT_EXTENT,MIN_EXTENTS,
  MAX_EXTENTS,PCT_INCREASE,MIN_EXTLEN,STATUS,
  CONTENTS,LOGGING,
  EXTENT_MANAGEMENT, -- Columns not available in v8.0.x
  ALLOCATION_TYPE, -- Remove these columns if running
  PLUGGED_IN, -- against a v8.0.x database
  SEGMENT_SPACE_MANAGEMENT --use only in v9.2.x or later
  FROM DBA_TABLESPACES
  ORDER BY TABLESPACE_NAME;
   
  --碎片信息
  select tablespace_name,
         sqrt(max(blocks) / sum(blocks)) * (100 / sqrt(sqrt(count(blocks)))) FSFI
    from dba_free_space
   group by tablespace_name;
   
  --所有表空间的大小和当前使用率
  SELECT tablespace_name, max_blocks, count_blocks, sum_free_blocks
  , to_char(100*sum_free_blocks/sum_alloc_blocks, '99.99') || '%'
  AS pct_free
  FROM ( SELECT tablespace_name
  , sum(blocks) AS sum_alloc_blocks
  FROM dba_data_files
  GROUP BY tablespace_name
  )
  , ( SELECT tablespace_name AS fs_ts_name
  , max(blocks) AS max_blocks
  , count(blocks) AS count_blocks
  , sum(blocks) AS sum_free_blocks
  FROM dba_free_space
  GROUP BY tablespace_name )
  WHERE tablespace_name = fs_ts_name;

  --查出最大读的热点文件
  select * from (select t.NAME tbs_name ,substr(C.name,1,50) file_Name, 
   C.status, C.bytes/1024/1024||'M' bytes_in_M, D.phyrds 
   from v$datafile C, v$filestat D ,v$tablespace t
   where C.file# = D.file# and t.TS#=c.TS#
  order by D.phyrds desc ) where rownum < 6;
   
  --sessionwait
  select a.sid,b.sql_text,a.machine,a.program,a.osuser,c.event,c.p1,c.p2,c.p3
  from v$session a,v$sql b,v$session_wait c
  where a.sql_hash_value=b.hash_value
  and a.sid=c.sid
  and c.event not like '%SQL%'
  order by sid;
   
  --查出最大写的热点文件
  select * from (select t.NAME tbs_name ,substr(C.name,1,50) file_Name, 
   C.status, C.bytes/1024/1024||'M' bytes_in_M, D.phywrts
   from v$datafile C, v$filestat D ,v$tablespace t
   where C.file# = D.file# and t.TS#=c.TS#
  order by D.phyrds desc ) where rownum < 6;

   
  --最近的归档日志生成信息
  --每天的归档日志生成统计
  select   nvl(substr(to_char(FIRST_TIME,'YYYY/MM/DD,DY'),1,15),'总计:') as get_date,
  count(*)as log_counts,trunc(sum(t.BLOCKS*t.BLOCK_SIZE)/1024/1024)||'M' as logfile_size
  from     v$archived_log t 
  group by rollup(substr(to_char(FIRST_TIME,'YYYY/MM/DD,DY'),1,15))
  order by substr(to_char(FIRST_TIME,'YYYY/MM/DD,DY'),1,15) desc;

   
  --当前重做日志的信息
  select   a.MEMBER,
           b.GROUP#,
           b.THREAD#,
           b.SEQUENCE#,
           b.BYTES,
           b.MEMBERS,
           b.ARCHIVED,
           b.STATUS,
           b.FIRST_CHANGE#,
           b.FIRST_TIME
  from     sys.v_$logfile a, sys.v_$log b
  where    a.GROUP# = b.GROUP#
  order by a.group#;
   
  /*应备份的数据库所有文件（物理全备）
  列出所有的数据库相关文件，需要了解数据库的物理备份所需要备份的目标文件
  客户端，建议使用PLSQL Developer*/
  SELECT   rownum ,t.*
      FROM (SELECT 'data      file' AS TYPE, t1.file_name AS file_name,
                   t1.tablespace_name
                         AS tbs_name,
                   t1.bytes / 1024 / 1024 || 'M' AS size_in_mbytes,
                   t1.autoextensible
                         AS autoextensible, t1.status AS status
              FROM dba_data_files t1, v$datafile t2
             WHERE t1.file_name = t2.NAME
            UNION
            SELECT 'data file(temporary)' AS TYPE, t1.file_name AS file_name,
                   t1.tablespace_name
                         AS tbs_name,
                   t1.bytes / 1024 / 1024 || 'M' AS size_in_mbytes,
                   t1.autoextensible
                         AS autoextensible, t1.status AS status
              FROM dba_temp_files t1, v$tempfile t2
             WHERE t1.file_name = t2.NAME
            UNION
            SELECT 'redo    file' AS TYPE, l2.MEMBER AS file_name,
                   'thread:' || l1.thread# || '_group:' || l1.group#
                         AS tbs_name,
                   bytes / 1024 / 1024 || 'M' AS size_in_mbytes, '- - -',
                   l1.status || '_' || l2.status
                         AS status
              FROM v$log l1, v$logfile l2
             WHERE l1.group# = l2.group#
            UNION
            SELECT 'control file' AS TYPE, NAME AS file_name, '- - -' AS tbs_name,
                   '- - -'
                         AS size_in_mbytes, '- - -' AS autoextensible, status
              FROM v$controlfile
      UNION
            SELECT 'sp file' AS TYPE, value AS file_name, 'inst_id:'||inst_id AS tbs_name,
                   '- - -'
                         AS size_in_mbytes, '- - -' AS autoextensible, '- - -' as status
              FROM gv$parameter where name like '%spfile%') t
  ORDER BY 2;
   
  /*mount点的数据大小分布
  PLSQL Developer 执行
  当前数据库的所有文件在多个mount点的数据分布明细和汇总情况*/
  select nvl(type, 'all size'),
         substr(name, 1, 16),
         decode(sum(bytes) / 1024 / 1024 || 'M',
                '0M',
                '',
                sum(bytes) / 1024 / 1024 || 'M')
    from (select 'datafile' as type, name, t.bytes as bytes
            from v$datafile t
          union
          select 'tempfile' as type, name, t.bytes as bytes
            from v$tempfile t
          union
          select 'control' as type, name, 0 as bytes
            from v$controlfile t
          union
          select 'logfile' as type, member as name, bytes as bytes
            from (select member, bytes
                    from v$logfile t1, v$log t2
                   where t1.GROUP# = t2.GROUP#) t3)
   group by rollup(substr(name, 1, 16), type);
   
  select nvl(substr(name, 1, 17), '所有文件系统') filesystem,
         nvl(type, '文件总计') type,
         decode(sum(bytes) / 1024 / 1024 || 'M',
                '0M',
                '',
                sum(bytes) / 1024 / 1024 || 'M') bytes_in_M
    from (select 'datafile' as type, name, t.bytes as bytes
            from v$datafile t
          union
          select 'tempfile' as type, name, t.bytes as bytes
            from v$tempfile t
          union
          --select 'control' as type,name,0 as bytes from v$controlfile t 
          --union
          select 'logfile' as type, member as name, bytes as bytes
            from (select member, bytes
                    from v$logfile t1, v$log t2
                   where t1.GROUP# = t2.GROUP#) t3)
   group by rollup(substr(name, 1, 17), type);
   
  --检查无效的索引
  select * from dba_indexes t where t.status = 'INVALID';
   
  /*检查无效的trigger 
  查询结果和应用有关，应与应用开发人员协调 */ 
  SELECT owner, trigger_name, table_name, status FROM dba_triggers 
  WHERE status = 'DISABLED' and owner not in ('SYS','SYSTEM') ;
   
  /*检查不起作用的约束 
  sqlplus 执行
  查询结果和应用有关，应与应用开发人员协调*/
  SELECT owner, constraint_name, table_name, constraint_type, status 
  FROM dba_constraints WHERE status = 'DISABLED' 
   and owner not in ('SYS','SYSTEM') ;
   
  /*查出主键失效的表
  sqlplus 执行
  查询结果和应用有关，应与应用开发人员协调*/
  SELECT owner, constraint_name, table_name, status 
  FROM all_constraints 
  WHERE owner not in ('SYS','SYSTEM')  AND status = 'DISABLED' 
  AND constraint_type = 'P' ;
   

  /*查出没有主键的表
  sqlplus 执行
  查询结果和应用有关，应与应用开发人员协调*/
  SELECT table_name ,owner
  FROM dba_tables where owner not in ('SYS','SYSTEM')
  MINUS 
  SELECT table_name ,owner
  FROM dba_constraints 
  Where  owner not in ('SYS','SYSTEM')
  And constraint_type = 'P' ;
  /* 
  --获得当前重建数据库所需要的ddl和用户信息
  ----要结合exp出的dmp文件,脚本内容如下:
  ----prompt scrpit begin --------
  prompt
  --prompt *********** 1 当前初始化参数文件内容 ***********************************

  set pagesize 0
  select g2.value||'.'||g1.name||'='||g1.value from 
  (select * from gv$parameter  where ISDEFAULT='FALSE') g1 ,
  (select INST_ID,value from gv$parameter where name='instance_name') g2
  where g1.INST_ID=g2.inst_id  
  order by g1.name
  /
   
  prompt
  prompt *************** 2  数据库信息 ***************
  select t.INST_ID,t.DBID,t.NAME ,t.LOG_MODE,t.OPEN_MODE,(select value from v$parameter where name='db_block_size') as db_block_size from gv$database t
  /
   
  prompt
  prompt *************** 3 实例信息 ***************
  select  '实例id:'||INST_id||',实例号:'||INSTANCE_number||',线程号:'||thread#||' --- 实例名:'||INSTANCE_name||',状态:'||status||',机器名:'||host_name ||',logins: '||logins||',---'||version as info from gv$instance
  /
   
  prompt
  prompt **************** 4 字符集信息 ********************************************
  select decode(parameter,'NLS_CHARACTERSET','数据库字符集charset','NLS_NCHAR_CHARACTERSET','国家字符集ncharset',parameter),value  from nls_database_parameters where parameter like '%CHARACTERSET%'
  /
   
  prompt
  prompt **************** 5 表空间信息 ********************************************
  SET  serveroutput on
  EXEC dbms_output.enable(20000000)

  DECLARE
     v1   VARCHAR2 (2);
     v2   VARCHAR2 (200);
     n1   NUMBER;
  BEGIN
     DBMS_OUTPUT.put_line ('---ts scripts begin!---');
     n1 := 1;
     FOR i IN (SELECT   tablespace_name a, COUNT (*) counts
                   FROM dba_data_files
               GROUP BY tablespace_name
               UNION
               SELECT   tablespace_name a, COUNT (*) counts
                   FROM dba_temp_files
               GROUP BY tablespace_name)
     LOOP
        DBMS_OUTPUT.put_line ('---' || n1 || ': ' || i.a);
        n1 := n1 + 1;
        SELECT DECODE (
                  CONTENTS,
                  'TEMPORARY', 'create TEMPORARY tablespace ',
                  'UNDO', 'create undo tablespace ',
                  'create tablespace '
               )
          INTO v2
          FROM dba_tablespaces
         WHERE tablespace_name = i.a;
        DBMS_OUTPUT.put_line (v2 || i.a || ' datafile ');
        FOR ii IN (SELECT ROWNUM, tablespace_name a, file_name b,
                          bytes / 1024 / 1024 || 'M' c
                     FROM dba_data_files
                    WHERE tablespace_name = i.a
                   UNION
                   SELECT ROWNUM, tablespace_name a, file_name b,
                          bytes / 1024 / 1024 || 'M' c
                     FROM dba_temp_files
                    WHERE tablespace_name = i.a)
        LOOP
           IF i.counts = 1
           THEN
              v1 := '';
           ELSIF i.counts = ii.ROWNUM
           THEN
              v1 := ' ';
           ELSE
              v1 := ',';
           END IF;
           DBMS_OUTPUT.put_line (
              '''' || ii.b || ''' size ' || ii.c || ' autoextend off' || v1
           );
        END LOOP;
        DBMS_OUTPUT.put_line (
           'EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT  auto '
        );
        DBMS_OUTPUT.put_line ('/');
        DBMS_OUTPUT.put_line (' ');
     END LOOP;
     DBMS_OUTPUT.put_line ('---ts scripts finished!---');
  END;
  /

  prompt
  prompt **************** 6 用户信息 ********************************************
  SELECT   rownum, 
  'create user '       || username       || chr(10) ||'identified by values '''       || PASSWORD       
   || '''' || chr(10) ||'default tablespace '       || decode(default_tablespace,'SYSTEM','USERS',default_tablespace)      
  || chr(10) ||'temporary tablespace '       || temporary_tablespace       || ';' 
  FROM dba_users  
  where username not in ('SYS','SYSTEM','DBSNMP','OUTLN','WMSYS')
  /
   
  prompt
  prompt **************** 7 用户授权信息 ********************************************
  SELECT   rownum, 
  'grant ' || t.granted_role || ' to ' || grantee || ';'    
  FROM dba_role_privs t   WHERE t.grantee NOT IN ('SYS', 'SYSTEM')    and t.granted_role!='DBA'    
  and t.grantee in (select t1.username from dba_users t1 
  where username not in ('SYS','SYSTEM','DBSNMP','PERFSTAT','OUTLN','WMSYS'))ORDER BY t.grantee
  /
   
  prompt 
 */ 
end route_inspection;
/
