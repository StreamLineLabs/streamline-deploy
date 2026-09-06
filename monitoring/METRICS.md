# Streamline Metrics Contract

Every Prometheus metric referenced by the artifacts in this repository is
listed below. This file is the contract between deployment/SRE and the
Streamline core metrics owners, and `make metrics-contract` fails the build when
an artifact references a metric that is not listed here.

## Verification status — read this first

**No metric in this repository has been verified against the metrics that
Streamline core actually emits.** This repository contains no core source, and
the audit finding DEP-D-1 recorded that several dashboard and alert queries use
metric names that are absent from core, which renders silently empty panels and
alerts that can never fire. Renaming metrics on one side of the contract alone
would only move the breakage, so every entry below is marked `unverified` until
core publishes an authoritative list.

Treat `unverified` as: *this panel or alert may be permanently empty.*

### How to verify

```bash
# Against a running Streamline instance built from the pinned core commit:
curl -s http://localhost:9094/metrics | grep -E '^# (HELP|TYPE) streamline_' | sort
```

Compare that output with the table below, then either

1. update this repository's queries to the emitted names and flip the status to
   `emitted`, or
2. record the metric as `missing` and remove or disable the query that uses it —
   do not leave a query in place that silently returns no data.

### Known conflicting variants

These pairs/groups cannot all be correct; at most one spelling per group can be
the emitted name. They are the highest-priority entries to resolve.

| Concept | Competing names |
|---|---|
| Active connections | `streamline_active_connections`, `streamline_connections_active` |
| Bytes in/out | `streamline_bytes_in_total` / `streamline_bytes_out_total`, `streamline_bytes_received_total` / `streamline_bytes_sent_total` |
| Consumer lag | `streamline_consumer_group_lag`, `streamline_consumer_lag`, `streamline_consumer_lag_total` |
| Produce latency histogram | `streamline_produce_latency_seconds_bucket`, `streamline_produce_duration_seconds_bucket` |
| Fetch latency histogram | `streamline_fetch_latency_seconds_bucket`, `streamline_fetch_duration_seconds_bucket` |
| Stored bytes | `streamline_storage_bytes`, `streamline_storage_bytes_total` |
| Partition count | `streamline_partition_count`, `streamline_partitions_total`, `streamline_topic_partitions` |
| Message counters | `streamline_messages_produced_total` / `streamline_messages_consumed_total`, `streamline_messages_total`, `streamline_records_total` |
| Topic log size | `streamline_log_size_bytes`, `streamline_topic_log_size_bytes` |

## Referenced metrics

| Metric | Referenced by | Status |
|---|---|---|
| `streamline_active_connections` | `helm/streamline/templates/grafana-overview.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/README.md`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_branches_active` | `grafana/dashboards/branches.json` | unverified |
| `streamline_branches_completed_total` | `grafana/dashboards/branches.json` | unverified |
| `streamline_branches_failed_total` | `grafana/dashboards/branches.json` | unverified |
| `streamline_branches_operations_total` | `grafana/dashboards/branches.json` | unverified |
| `streamline_branches_storage_bytes` | `grafana/dashboards/branches.json` | unverified |
| `streamline_bytes_in_total` | `monitoring/README.md`, `monitoring/grafana/streamline-overview.json`, `monitoring/grafana/streamline-topics.json` | unverified |
| `streamline_bytes_out_total` | `monitoring/README.md`, `monitoring/grafana/streamline-overview.json`, `monitoring/grafana/streamline-topics.json` | unverified |
| `streamline_bytes_received_total` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_bytes_sent_total` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_cluster_leader_id` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_connections_active` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_consumer_commit_total` | `helm/streamline/templates/grafana-consumer-lag.yaml` | unverified |
| `streamline_consumer_fetch_total` | `helm/streamline/templates/grafana-consumer-lag.yaml` | unverified |
| `streamline_consumer_group_lag` | `helm/streamline/templates/grafana-consumer-lag.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/README.md`, `monitoring/grafana-cluster-dashboard.json`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/grafana/streamline-consumer-lag.json`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_consumer_group_rebalances_total` | `monitoring/grafana/streamline-consumer-lag.json` | unverified |
| `streamline_consumer_group_state` | `monitoring/grafana/streamline-consumer-lag.json` | unverified |
| `streamline_consumer_lag` | `k8s/keda/scaledobject.yaml` | unverified |
| `streamline_consumer_lag_total` | `k8s/keda/scaledobject.yaml` | unverified |
| `streamline_contract_attestations_total` | `grafana/dashboards/contracts.json` | unverified |
| `streamline_contract_bypass_active` | `grafana/dashboards/contracts.json` | unverified |
| `streamline_contract_rejections_total` | `grafana/dashboards/contracts.json` | unverified |
| `streamline_contract_validation_duration_seconds_bucket` | `grafana/dashboards/contracts.json` | unverified |
| `streamline_edge_connected_nodes` | `grafana/dashboards/edge-sync.json` | unverified |
| `streamline_edge_merge_events_total` | `grafana/dashboards/edge-sync.json` | unverified |
| `streamline_edge_pending_sync_operations` | `grafana/dashboards/edge-sync.json` | unverified |
| `streamline_edge_sync_latency_seconds_bucket` | `grafana/dashboards/edge-sync.json` | unverified |
| `streamline_fetch_duration_seconds_bucket` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_fetch_latency_seconds` | `monitoring/README.md` | unverified |
| `streamline_fetch_latency_seconds_bucket` | `helm/streamline/templates/grafana-overview.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_log_size_bytes` | `monitoring/grafana/streamline-topics.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_memory_decayed_total` | `grafana/dashboards/agent-memory.json` | unverified |
| `streamline_memory_recall_hits_total` | `grafana/dashboards/agent-memory.json` | unverified |
| `streamline_memory_recall_misses_total` | `grafana/dashboards/agent-memory.json` | unverified |
| `streamline_memory_remember_total` | `grafana/dashboards/agent-memory.json` | unverified |
| `streamline_memory_storage_bytes` | `grafana/dashboards/agent-memory.json` | unverified |
| `streamline_messages_consumed_total` | `helm/streamline/templates/grafana-overview.yaml`, `monitoring/README.md`, `monitoring/grafana-cluster-dashboard.json`, `monitoring/grafana/streamline-overview.json` | unverified |
| `streamline_messages_per_second` | `k8s/keda/scaledobject.yaml` | unverified |
| `streamline_messages_produced_total` | `helm/streamline/templates/grafana-overview.yaml`, `monitoring/README.md`, `monitoring/grafana-cluster-dashboard.json`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_messages_total` | `k8s/keda/scaledobject.yaml` | unverified |
| `streamline_multidc_replication_lag_ms` | `helm/streamline/templates/prometheusrule.yaml`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_partition_count` | `monitoring/README.md` | unverified |
| `streamline_partitions_total` | `monitoring/grafana-cluster-dashboard.json`, `monitoring/grafana/streamline-topics.json` | unverified |
| `streamline_produce_duration_seconds_bucket` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_produce_latency_seconds` | `monitoring/README.md` | unverified |
| `streamline_produce_latency_seconds_bucket` | `helm/streamline/templates/grafana-overview.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_records_total` | `monitoring/grafana/streamline-topics.json` | unverified |
| `streamline_request_duration_seconds_bucket` | `monitoring/grafana/streamline-consumer-lag.json`, `monitoring/grafana/streamline-topics.json` | unverified |
| `streamline_requests_total` | `monitoring/grafana/streamline-consumer-lag.json` | unverified |
| `streamline_segment_count` | `monitoring/README.md` | unverified |
| `streamline_semantic_embed_queue_depth` | `grafana/dashboards/semantic-topics.json` | unverified |
| `streamline_semantic_embeds_total` | `grafana/dashboards/semantic-topics.json` | unverified |
| `streamline_semantic_index_size_bytes` | `grafana/dashboards/semantic-topics.json` | unverified |
| `streamline_semantic_search_latency_seconds_bucket` | `grafana/dashboards/semantic-topics.json` | unverified |
| `streamline_storage_bytes` | `helm/streamline/templates/grafana-overview.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/README.md`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/grafana/streamline-overview.json`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_storage_bytes_total` | `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_storage_capacity_bytes` | `helm/streamline/templates/grafana-overview.yaml`, `helm/streamline/templates/prometheusrule.yaml`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_topic_log_size_bytes` | `helm/streamline/templates/grafana-topics.yaml` | unverified |
| `streamline_topic_messages_in_total` | `helm/streamline/templates/grafana-topics.yaml` | unverified |
| `streamline_topic_messages_out_total` | `helm/streamline/templates/grafana-topics.yaml` | unverified |
| `streamline_topic_partitions` | `helm/streamline/templates/grafana-topics.yaml` | unverified |
| `streamline_topics_total` | `helm/streamline/templates/grafana-overview.yaml`, `monitoring/grafana-cluster-dashboard.json` | unverified |
| `streamline_transaction_timeouts_total` | `monitoring/prometheus/alerts.yml` | unverified |
| `streamline_under_replicated_partitions` | `helm/streamline/templates/prometheusrule.yaml`, `monitoring/grafana-cluster-dashboard.json`, `monitoring/grafana/provisioning/alerting/rules.yml`, `monitoring/prometheus/alerts.yml` | unverified |

## Non-Streamline metrics in use

`up` and `process_resident_memory_bytes` come from Prometheus itself and from
the Rust process collector; they are outside this contract.
