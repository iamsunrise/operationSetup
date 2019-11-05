2.2  数据库表大小情况（大于10G的表）
检查方法：
select a.owner "用户名",
       b.table_name "表名",
       b.num_rows "表行数",
       round(sum(a.blocks) * 8 / 1024 / 1024, 2) "表大小（G）",
       b.last_analyzed "最后次分析时间"
  from dba_segments a,dba_tables b
  where a.segment_name=b.table_name
  group by a.owner,b.table_name,b.num_rows,b.last_analyzed
  having round(sum(a.blocks) * 8 / 1024 / 1024, 2)>10
  order by round(sum(a.blocks) * 8 / 1024 / 1024, 2) desc
  
  检查表空间使用情况
SELECT a.tablespace_name "表空间名",
       total "表空间大小",
       free "表空间剩余大小",
       (total - free) "表空间使用大小",
       total / (1024 * 1024 * 1024) "表空间大小(G)",
       free / (1024 * 1024 * 1024) "表空间剩余大小(G)",
       (total - free) / (1024 * 1024 * 1024) "表空间使用大小(G)",
       round((total - free) / total, 4) * 100 "使用率 %"
  FROM (SELECT tablespace_name, SUM(bytes) free
          FROM dba_free_space
         GROUP BY tablespace_name) a,
       (SELECT tablespace_name, SUM(bytes) total
          FROM dba_data_files
         GROUP BY tablespace_name) b
 WHERE a.tablespace_name = b.tablespace_name;
 
 
SELECT df.tablespace_name "表空间名",
      COUNT(file_name) "数据文件个数" ,	
      ROUND(MAX(free.maxbytes) / 1048576/1024,2)  "空闲最大块（G）",
       ROUND(SUM(df.BYTES) / 1048576/1024,2) "总空间（G）",
       ROUND(SUM(free.BYTES) / 1048576/1024,2) "空闲空间（G）",
       ROUND(SUM(df.BYTES) / 1048576/1024 - SUM(free.BYTES) / 1048576/1024,2) "已使用空间（G）",
       100 - ROUND(100.0 * SUM(free.BYTES) / SUM(df.BYTES),2) "已使用百分比（%）",
       ROUND(100.0 * SUM(free.BYTES) / SUM(df.BYTES),2) "空闲百分比（%）"
  FROM dba_data_files df,
       (SELECT tablespace_name,
               file_id,
               SUM(BYTES) BYTES,
               MAX(BYTES) maxbytes
          FROM dba_free_space
         GROUP BY tablespace_name, file_id) free
 WHERE df.tablespace_name = free.tablespace_name(+)
   AND df.file_id = free.file_id(+)
 GROUP BY df.tablespace_name
 order by "已使用空间（G）" desc;
 
 添加表空间数据文件
 ALTER TABLESPACE system ADD DATAFILE  
'+RACDB_DATA/racdb/datafile/system.256.1004785051' SIZE 50M;  


ALTER DATABASE DATAFILE '+RACDB_DATA/racdb/datafile/system.256.1004785051'  
RESIZE 1024M;
 
查看表数据文件情况
select b.file_name "物理文件名",
       b.tablespace_name "表空间",
       b.bytes / 1024 / 1024 "大小M",
       (b.bytes - sum(nvl(a.bytes, 0))) / 1024 / 1024 "已使用M",
       substr((b.bytes - sum(nvl(a.bytes, 0))) / (b.bytes) * 100, 1, 5) "利用率" from dba_free_space a,
       dba_data_files b where a.file_id = b.file_id group by b.tablespace_name,
       b.file_name,
       b.bytes order by b.tablespace_name;

查看数据库版本
SELECT version
  FROM product_component_version
 WHERE substr(product, 1, 6) = 'Oracle';

2.4  检查有无运行失败的JOB
select  job,
       this_date,
       this_sec,
       next_date,
       next_sec,
       failures,
       what
from dba_jobs
where failures !=0 and failures is not null;
