# CLAUDE.md — Streamline Deploy

## Overview
Deployment configurations for [Streamline](https://github.com/streamlinelabs/streamline): Docker images, Helm charts, Kubernetes manifests, and monitoring stack.

## Quick Start
```bash
scripts/prepare-core-context.sh                          # pinned core sources -> .build/core
make docker                                              # build streamline:dev from them
STREAMLINE_IMAGE=streamline:dev docker compose up -d      # Start via Docker
helm install streamline ./helm/streamline \
  --set image.repository=my-registry/streamline --set image.tag=<tag>
kubectl apply -k k8s/                                    # after `kustomize edit set image`
```
Nothing is published: no image tag and no chart repository. Every stack,
manifest and chart default requires an image you built, and falls back to a
local-only placeholder that matches nothing in any registry.

## Image Build Context
This repository ships **no Streamline core sources**. `Dockerfile`,
`Dockerfile.edge` and `playground/Dockerfile` all compile the core crates, so
their build context must be a checkout of the core repository at the immutable
commit pinned in `core-source.env` (`scripts/prepare-core-context.sh`, or
`make docker`). That script also overlays this repository's image assets under
`.deploy/`, which is how `Dockerfile.edge` gets its (unsupported, reference-only)
appliance config. Exactly one workflow —
`.github/workflows/docker-publish.yml` — publishes image tags; `release.yml`
packages the Helm chart only and publishes nothing.

## Image Editions
`STREAMLINE_EDITION` is a capability contract enforced in `Dockerfile`:
`standard` (no features, no capabilities), `full` (exactly
`STREAMLINE_FEATURES=full`, core's meta-feature → auth + clustering) and
`custom` (any other list, and `STREAMLINE_CAPABILITIES` must declare
`auth`/`clustering`/`moonshot`/`none`). The declaration is recorded in the
`dev.streamline.capabilities` label; the chart's `image.capabilities` mirrors it
for `custom` and is rejected for the other two. Helm never infers auth or
clustering for a custom image (`tests/image-editions_test.sh`).

## Publish Pipeline
`docker-publish.yml` pushes a staging reference (`:staging-<run>-<attempt>`)
first, but only after a tag push has been matched exactly to the pinned core
checkout's `[package].version`. That verified version is passed as
`STREAMLINE_VERSION` and written to the OCI version label. It then validates
that **digest** (strict compose smoke test, Trivy scan, SBOM,
cosign signature and attestations), and only then promotes the same digest to
the public semver/major-minor/latest tags with `imagetools create`, verifying
each tag resolves back to it. `docker/metadata-action` runs at promotion time
only. Promotion and SLSA provenance require `github.event_name == 'push'` plus
a `refs/tags/v…` ref, so `workflow_dispatch` (including a `core_ref` override
with an existing tag selected) is validation-only
(`tests/publish-pipeline_test.sh`).

## Architecture
```
├── Dockerfile                    # Multi-stage Rust build, non-root, minimal runtime
│                                 # (context = pinned core checkout, not this repo)
├── Dockerfile.edge               # UNSUPPORTED reference only: never built, published
│                                 #  or run; no MQTT/1883 claim (edge runtime unverified)
├── core-source.env               # Pinned Streamline core commit for image builds
├── scripts/
│   ├── prepare-core-context.sh   # Materialises the pinned core checkout + overlay
│   └── install.sh                # Binary installer (mandatory checksum verification)
├── docker-compose.yml            # Production single-node setup
├── docker-compose.test.yml       # Integration test setup
├── docker-compose.demo.yml       # Demo with pre-seeded topics
├── docker-compose.kafka-clients.yml  # Kafka client compatibility testing
├── docker/
│   ├── Dockerfile.seed           # Data seeding image
│   ├── prometheus.yml            # Prometheus scrape config
│   └── docker-compose.benchmarks.yml
├── helm/streamline/
│   ├── Chart.yaml                # v0.4.0
│   ├── values.yaml               # Default values (security-hardened)
│   ├── values.schema.json        # JSON Schema validation
│   └── templates/
│       ├── statefulset.yaml      # StatefulSet with PVCs
│       ├── service.yaml          # Headless + LoadBalancer
│       ├── configmap.yaml        # Server configuration
│       ├── networkpolicy.yaml    # Pod-to-pod traffic rules
│       ├── servicemonitor.yaml   # Prometheus ServiceMonitor
│       ├── hpa.yaml              # HPA (rejected: horizontal scaling unsupported)
│       └── pdb.yaml              # PodDisruptionBudget
├── k8s/                          # Raw Kubernetes manifests + Kustomize
│                                 # (single standalone broker; k8s/keda is an
│                                 #  unsupported example, not in the base)
├── demos/                        # Entry points; edge and CDC fail closed (unsupported)
├── tests/                        # Shell characterization tests and static gates
└── monitoring/
    ├── docker-compose.monitoring.yml  # Prometheus + Grafana sidecar
    ├── METRICS.md                # Metric contract + verification status
    ├── prometheus/alerts.yml     # Alerting rules (metric names UNVERIFIED)
    └── grafana/streamline-overview.json  # 18-panel dashboard
```

## Security Defaults (Helm)
- `readOnlyRootFilesystem: true` with `/tmp` emptyDir
- `runAsNonRoot: true`, user 1000
- `allowPrivilegeEscalation: false`, drop ALL capabilities
- `networkPolicy.enabled: true` (same-namespace only on 9092/9094)
- TLS is available in every image and needs no capability, and it protects the
  **Kafka listener (9092) only** — the HTTP API on 9094 stays plaintext (the
  probes use it that way), so HTTPS for it is an ingress/reverse-proxy concern
  and there is no HTTP mTLS (`tests/tls-scope_test.sh`).
- SASL auth requires a declared image capability (`image.edition: full`, or
  `image.edition: custom` with an explicit `image.capabilities` list). Moonshot
  settings are not wired by any template, so any `moonshot.*.enabled: true`
  fails the render — declaring `moonshot` in `image.capabilities` does not make
  them take effect.
- `image.tag` ships empty: no image is published, so the render fails until an
  operator names one. Listener ports are fixed (Kafka 9092, HTTP 9094) and
  custom values are rejected by `values.schema.json` before render and by the
  chart's own guard (`tests/listener-ports_test.sh`).
- `config.autoCreateTopics` is always rendered as
  `STREAMLINE_AUTO_CREATE_TOPICS` ("true"/"false"): core defaults it to on, so
  omitting the variable would ignore an explicit `false`.
- Clustered (`config.clusterEnabled`) or multi-replica deployments are rejected
  until peer bootstrap is implemented. `autoscaling.enabled` and `keda.enabled`
  are rejected for the same reason: an autoscaler writes the StatefulSet's
  replica count itself and would bypass the `replicaCount > 1` guard.
- The raw manifests in `k8s/` deploy one standalone broker: `configmap.yaml`
  sets `STREAMLINE_AUTO_CREATE_TOPICS: "false"` explicitly (core defaults it to
  on) and `k8s/keda/` is an unsupported example that is not part of the applied
  kustomization.
- Settings removed in the auth/TLS rewiring (`auth.sasl.username`/`password`,
  `tls.mutualTls`, `tls.certSecretName`, top-level `extraArgs`, …) fail the
  render with a migration hint instead of being silently dropped.

## Validation
```bash
make test    # helm lint/validate/unittest, shell syntax, shell tests, compose config
make lint    # helm lint + shellcheck
make static  # release gates: image build context, single publisher, publish
             # pipeline ordering/digest identity, core-pin fail-closed, image
             # editions, OCI reference normalization, TLS scope, listener
             # ports, published-artifact claims, disabled installer advertising,
             # playground image contract, disabled edge/CDC demos, metric
             # contract, scaling claims, moonshot + feature-gated demo claims,
             # compose gate
```
`make compose-config` (a `make test` prerequisite) runs `docker compose config`
over every `docker-compose*.yml`: it pulls nothing, starts nothing, and stops at
the first invalid file. The `|| exit 1` in that loop is load-bearing — a shell
`for` loop otherwise reports only the last iteration's status
(`tests/makefile-compose-gate_test.sh`).

## Known Gaps
- `core-source.env` carries no commit yet. Image builds fail closed, and the CI
  `image-build` job **fails** (it is not skipped): the resolver runs
  unconditionally and no step is guarded by `if:`, `continue-on-error` or
  `|| true`, so an unbuildable repository cannot report a green image gate
  (`tests/core-pin-gate_test.sh`). Pinning a 40-character SHA is the only thing
  that turns it green.
- Nothing is published: no image tag, no chart repository. Compose stacks,
  raw manifests and the chart all require an explicitly supplied image and fall
  back to unpullable local placeholders (`tests/published-artifacts_test.sh`).
- The prebuilt binary installer is unavailable too: `scripts/install.sh` exits
  before network or filesystem mutation until a controlled endpoint and
  verified release archive set exist
  (`tests/installer-availability_test.sh`).
- Dashboard and alert metric names are unverified against core
  (`monitoring/METRICS.md`).
- The moonshot features are compile-time cargo features and no published tag is
  built with them, so `docker-compose.moonshot-demo.yml` has no runnable default
  image: it needs `STREAMLINE_MOONSHOT_IMAGE` pointing at an image built with
  `--build-arg STREAMLINE_FEATURES=moonshot` and fails closed without it
  (`tests/moonshot-demo_test.sh`). Core reads no `STREAMLINE_FEATURES` variable,
  so no Compose stack may claim features through the environment;
  `tests/feature-gated-demos_test.sh` sweeps every `docker-compose*.yml` for
  runtime feature variables.
- The CDC demo is **disabled**: its routes, request body, message path and
  StreamQL endpoint are unverified, so every service sits behind the `disabled`
  Compose profile and `demos/cdc-demo.sh` exits non-zero. No artifact may
  present `/api/v1/cdc/sources` or `/sql` as a runnable instruction
  (`tests/cdc-demo-disabled_test.sh`).
- Edge is **unsupported**: the MQTT bridge on 1883, store-and-forward and cloud
  sync are unverified against core, so `docker-compose.edge.yml` was removed,
  `demos/edge-pilot.sh` fails closed without touching Docker, `Dockerfile.edge`
  is a reference that no longer exposes 1883, and the bundled edge config ships
  its `[edge]`/`[mqtt]` sections disabled (`tests/edge-unsupported_test.sh`).
- The official publisher currently releases `linux/amd64` only. Do not add
  `linux/arm64` to the manifest until the workflow smoke-tests and scans that
  platform before promotion.

## Ports
- **9092** — Kafka wire protocol (fixed; the chart rejects other values)
- **9094** — HTTP API: health, metrics, management (fixed; plaintext HTTP —
  terminate TLS at an ingress/reverse proxy)
- **9093** — reserved for inter-broker traffic; nothing listens in standalone mode

## Monitoring
```bash
# Start with monitoring sidecar (STREAMLINE_IMAGE names an image you built)
STREAMLINE_IMAGE=streamline:dev \
  docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
# Grafana: http://localhost:3000 (admin/streamline)
# Prometheus: http://localhost:9090
```
