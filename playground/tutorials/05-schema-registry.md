# Tutorial 5: Schema Registry

Manage schemas for data governance and compatibility checking.

## Step 1: Register a Schema

```bash
curl -X POST http://localhost:9094/api/schemas/subjects/user-events-value/versions \
  -H "Content-Type: application/json" \
  -d '{
    "schema_type": "JSON",
    "schema": "{\"type\":\"object\",\"properties\":{\"user_id\":{\"type\":\"string\"},\"action\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"integer\"}},\"required\":[\"user_id\",\"action\"]}"
  }'
```

## Step 2: Check Compatibility

```bash
# Add a new optional field (backward compatible)
curl -X POST http://localhost:9094/api/schemas/compatibility/subjects/user-events-value/versions/latest \
  -H "Content-Type: application/json" \
  -d '{
    "schema_type": "JSON",
    "schema": "{\"type\":\"object\",\"properties\":{\"user_id\":{\"type\":\"string\"},\"action\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"integer\"},\"metadata\":{\"type\":\"object\"}},\"required\":[\"user_id\",\"action\"]}"
  }'
```

## Step 3: Use in SDK

```python
from streamline_sdk import StreamlineClient

client = StreamlineClient("localhost:9092")
# Schema validation happens automatically when producing
await client.produce("user-events", {"user_id": "alice", "action": "login"})
```

