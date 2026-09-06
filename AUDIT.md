# Clean Code and SRP Audit

## Summary

- **Highest-leverage split:** separate `docker/seed-data.sh` into runtime
  transport/readiness and demo-fixture units so SRE changes do not edit product
  sample data.
- `helm/streamline/templates/grafana-dashboards.yaml` packages three dashboards
  for different operator personas in one review unit.
- The chart's long `values.yaml` is a deliberate public configuration surface,
  not an SRP violation; splitting it would fragment the Helm API.
- Monitoring rules and dashboard JSON are long but cohesive observability
  artifacts and should remain independent rather than share a generic library.
- Cross-repo metric-name drift is higher severity than local structure, but it
  requires a core/deploy contract decision and is therefore deferred.

## Findings

| ID | Location | Category | Severity | Actors in conflict | Cost | Size | Behavior risk |
|---|---|---|---|---|---|---|---|
| DEP-SRP-1 | `docker/seed-data.sh:1-181` | SRP | P2 | demo/product content; runtime operations | Readiness, HTTP transport, topic provisioning, and four fixture catalogs change in one script; an ops retry change conflicts with demo-content edits. | M | Medium |
| DEP-SRP-2 | `helm/streamline/templates/grafana-dashboards.yaml:1-179` | SRP | P2 | platform overview; consumer operations; topic operations | Three independently reviewed dashboards share one template and cannot be tested or changed in isolation. | M | Low |
| DEP-CC-1 | `docker/seed-data.sh:13-45` | Hidden error policy | P2 | demo idempotency; deployment diagnostics | Topic/message HTTP failures are intentionally swallowed, but the function names and final success summary do not expose partial failure. | S | Medium |
| DEP-D-1 | `helm/streamline/templates/grafana-dashboards.yaml`; core `src/metrics/mod.rs` | Cross-repo contract | P1 | core metrics owners; deployment/SRE | Several dashboard and alert queries use metric names absent from core, producing silent empty panels. | M | High |

## Actor and State Partition

### `docker/seed-data.sh`

| Partition | Functions/state | Actor/axis |
|---|---|---|
| Runtime | `HOST`, `HTTP_PORT`, `BASE_URL`, `TOTAL_MESSAGES`, `wait_for_server`, `create_topic`, `produce_message` | SRE; transport, readiness, retry/error policy |
| Fixtures | `TOPICS`, `create_topics`, `seed_events`, `seed_logs`, `seed_metrics`, `seed_orders` | Product/demo; sample domain content |
| Orchestration/presentation | banner, call ordering, final summary | Demo operator; workflow presentation |

Resulting units: `seed-runtime.sh`, `seed-fixtures.sh`, and the existing
`seed-data.sh` as the orchestration entry point. The new units own real
decisions and are independently characterizable; no forwarding class or
interface is introduced.

### Grafana dashboard template

The three ConfigMaps share chart metadata but not dashboard content. Resulting
units: `grafana-overview.yaml`, `grafana-consumer-lag.yaml`, and
`grafana-topics.yaml`, with one narrowly named Helm helper for the shared
Grafana discovery metadata.

## Ordered Refactor Sequence

1. Add shell characterization coverage for topic/message call counts and final
   summary output.
2. Add Helm unit coverage for all three dashboard ConfigMaps.
3. Move runtime and fixture functions unchanged into sourced shell units.
4. Name retry constants and fixture orchestration after the move.
5. Move each Grafana ConfigMap unchanged into its own template.
6. Consolidate only the shared Grafana discovery metadata in a Helm helper.
7. Run `make test lint` after every commit.

## Deferred

- Metric names and dashboard PromQL require a cross-repo contract decision; do
  not rename core or deploy metrics in this repository alone.
- Live smoke tests require a buildable/published Streamline image and remain
  outside this local structural refactor.
- The seeder's swallowed HTTP failures are preserved until product decides
  whether idempotent reruns or fail-fast diagnostics are the public behavior.

## Out of Scope

- `helm/streamline/values.yaml`: one public chart-configuration actor despite
  its length.
- `helm/streamline/values.schema.json`: schema for that same public contract.
- Grafana dashboard JSON and Prometheus alert files: each has one
  observability/presentation axis.
- Docker Compose variants and raw Kubernetes manifests: separate deployment
  products that only resemble one another; deduplicating them would couple
  different operational actors.
