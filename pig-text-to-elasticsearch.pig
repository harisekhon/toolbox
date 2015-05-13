--
--  Author: Hari Sekhon
--  Date: 2015-03-19 22:36:22 +0000 (Thu, 20 Mar 2015)
--
--  vim:ts=4:sts=4:sw=4:et
--

-- Pig script to index [bz2 compressed] text files or logs for fast source file lookups in Elasticsearch
--
-- This was a simple use case where I didn't need to parse the logs as it's more oriented around finding source data files based on full-text search.

-- Tested on Pig 0.14 (Tez/MapReduce) on Hortonworks HDP 2.2

-- http://www.elastic.co/guide/en/elasticsearch/hadoop/current/pig.html

-- USAGE:
--
-- must download Elasticsearch connector for Hadoop from here:
--
-- https://www.elastic.co/downloads/hadoop
-- 
-- hadoop fs -put elasticsearch-hadoop.jar
--
-- pig -p path=/data/logs -p index=logs -p type=myType pig-text-to-elasticsearch.pig

REGISTER 'elasticsearch-hadoop.jar';

--%default path   '/data';
--%default index  'myIndex';
--%default type   'myType';

-- Elasticsearch configuration
--
-- http://www.elastic.co/guide/en/elasticsearch/hadoop/current/configuration.html
--
%default es_nodes 'localhost:9200';
%default es_port  '9200'; -- only used for es.nodes not containing ports

%default queue 'default';

DEFINE EsStorage org.elasticsearch.hadoop.pig.EsStorage('es.http.timeout = 5m',
                                                        'es.index.auto.create = true', -- should pre-create index with tuned settings, but this is convenient for testing
                                                        'es.nodes = $es_nodes',
                                                        'es.port  = $es_port');
set default_parallel 5;
set pig.noSplitCombination true;

-- use dedicated queue to limit containers and resource consumption to not overwhelm Elasticsearch, otherwise loses a handful out of a millions of doc inserts as Elasticsearch throttle merges, causing task failures, which would then either retry, resulting in duplicates with autogenerated IDs, or failing the entire job
--
-- doesn't work with tez even via -D
--set tez.queue.name 'es';
-- but this works even for tez - however it overrides -Dmapreduce.job.queuename
set mapreduce.job.queuename '$queue';

-- don't retry I don't want duplicates since using autogenerated IDs, instead fail job => tune => retry
set mapreduce.map.maxattempts 1;
set mapreduce.reduce.maxattempts 1;

set mapreduce.map.speculative false;
set mapreduce.reduce.speculative false;

lines  = LOAD '$path' USING PigStorage('\n', '-tagPath') AS (path:chararray, line:chararray);

-- preserve whitespace but check and remove lines that are only whitespace
lines2 = FILTER lines BY line IS NOT NULL AND TRIM(line) != '';

-- strip redundant prefixes like hdfs://nameservice1 or file: to avoid storing the same bytes over and over without value
--lines_final = FOREACH lines2 GENERATE REPLACE(path, '^file:', '') AS path, line;
lines_final = FOREACH lines2 GENERATE REPLACE(path, '^hdfs://\\w+(?::\\d+)?', '') AS path, line;

STORE lines_final INTO '$index/$type' USING EsStorage;
