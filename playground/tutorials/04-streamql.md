# Tutorial 4: StreamQL — SQL on Streams

Query your streaming data using familiar SQL syntax.

## Step 1: Create Sample Data

```bash
streamline-cli topics create metrics --partitions 1
streamline-cli produce metrics \
  --template '{"host": "server-{{random:1:5}}", "cpu": {{random:10:95}}, "memory": {{random:30:90}}, "ts": {{timestamp}}}' \
  -n 10000
```

## Step 2: Batch Queries

```bash
# Average CPU by host
streamline-cli query "SELECT 
  JSON_EXTRACT(value, '$.host') as host,
  AVG(CAST(JSON_EXTRACT(value, '$.cpu') AS DOUBLE)) as avg_cpu
FROM topic('metrics')
GROUP BY host
ORDER BY avg_cpu DESC"

# Recent high-CPU events
streamline-cli query "SELECT * FROM topic('metrics') 
WHERE CAST(JSON_EXTRACT(value, '$.cpu') AS INT) > 90
LIMIT 20"
```

## Step 3: Continuous Queries

```bash
# Real-time alerting (streaming mode)
streamline-cli query "SELECT * FROM topic('metrics') 
WHERE CAST(JSON_EXTRACT(value, '$.cpu') AS INT) > 90
EMIT CHANGES"
```
