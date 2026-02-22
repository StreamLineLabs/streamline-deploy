# Production Monitoring for Streamline

Pre-built monitoring configurations for Streamline deployments.

## Quick Start

### Prometheus + Grafana (Docker Compose)

```bash
# From the streamline-deploy directory:
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

This starts Streamline with Prometheus scraping metrics from `:9094/metrics` and Grafana dashboards pre-loaded.

### Manual Setup

1. **Prometheus**: Import `prometheus/alerts.yml` into your Prometheus instance
2. **Grafana**: Import `grafana/streamline-overview.json` as a dashboard

## Contents

```
monitoring/
├── README.md                              # This file
├── docker-compose.monitoring.yml          # Prometheus + Grafana sidecar
├── grafana-cluster-dashboard.json         # Cluster overview dashboard (16 panels)
├── prometheus/
│   └── alerts.yml                         # Alerting rules
└── grafana/
    └── streamline-overview.json           # Grafana dashboard
```

## Prometheus Metrics

Streamline exposes Prometheus metrics at `http://<host>:9094/metrics` when the `metrics` feature is enabled.

### Key Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `streamline_messages_produced_total` | Counter | Total messages produced |
| `streamline_messages_consumed_total` | Counter | Total messages consumed |
| `streamline_bytes_in_total` | Counter | Total bytes received |
| `streamline_bytes_out_total` | Counter | Total bytes sent |
| `streamline_active_connections` | Gauge | Current open connections |
| `streamline_partition_count` | Gauge | Number of partitions |
| `streamline_consumer_group_lag` | Gauge | Consumer group lag by topic/partition |
| `streamline_produce_latency_seconds` | Histogram | Produce request latency |
| `streamline_fetch_latency_seconds` | Histogram | Fetch request latency |
| `streamline_storage_bytes` | Gauge | Disk usage by topic |
| `streamline_segment_count` | Gauge | Number of open segments |

## Alerting

See `prometheus/alerts.yml` for pre-configured alerts covering:
- High produce/consume latency (p99 > 100ms)
- Consumer group lag exceeding threshold
- Disk usage above 80%
- Connection count near limit
- Server not responding to health checks
