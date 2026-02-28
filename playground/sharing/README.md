# Playground Sharing

## Architecture

Shareable playground scenarios are stored as JSON blobs in object storage (S3/GCS) and accessed via unique URLs.

### URL Format
```
https://playground.streamline.dev/s/{scenario_id}
```

### Scenario Format
```json
{
  "id": "abc123",
  "version": 1,
  "created_at": "2026-03-04T10:00:00Z",
  "title": "CDC Pipeline Demo",
  "description": "Demonstrates Change Data Capture from PostgreSQL",
  "topics": [
    { "name": "cdc-events", "partitions": 3 }
  ],
  "commands": [
    "streamline-cli produce cdc-events -m '{\"user\": \"alice\"}'",
    "streamline-cli consume cdc-events --from-beginning"
  ],
  "preload_data": true
}
```

### API Endpoints
```
POST /api/playground/scenarios     → Create scenario, returns {id, url}
GET  /api/playground/scenarios/:id → Load scenario config
POST /api/playground/scenarios/:id/fork → Fork a scenario
```

### Storage
- Scenarios stored in S3: `s3://streamline-playground/scenarios/{id}.json`
- TTL: 90 days for anonymous, unlimited for authenticated users
- Max scenario size: 1MB
