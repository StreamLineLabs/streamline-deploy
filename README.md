# Streamline Deploy

[![CI](https://github.com/streamlinelabs/streamline-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/streamlinelabs/streamline-deploy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://docs.docker.com/compose/)
[![Helm](https://img.shields.io/badge/Helm-3.x-0F1689.svg)](https://helm.sh/)
[![Release](https://img.shields.io/github/v/release/streamlinelabs/streamline-deploy?label=release)](https://github.com/streamlinelabs/streamline-deploy/releases)

Deployment artifacts for [Streamline](https://github.com/streamlinelabs/streamline) — Helm charts, Kubernetes manifests, and Docker configurations.

## Status: no published image yet

**Nothing in this repository can be pulled from a registry today.** The official
image is built from a pinned Streamline *core* commit, and
[`core-source.env`](core-source.env) does not name one yet, so the single
publisher ([`docker-publish.yml`](.github/workflows/docker-publish.yml)) has
never pushed a tag. The Helm chart is likewise packaged as a CI artifact rather
than published to a chart repository.

Every stack, manifest and chart default therefore requires an image **you**
build, and each one fails closed on a local-only placeholder that matches
nothing in any registry rather than sending you at a tag nobody pushed. The CI
image gate is red for the same reason — see [Release gates](#release-gates).

The retained `scripts/install.sh` implementation is also disabled: there is no
controlled installer endpoint or verified release archive set. Invoking it
fails before any download or filesystem mutation. Build the core binaries from
source or build the local image described below.

## Try It — build from source

```bash
# 1. Materialise the pinned Streamline core sources into .build/core
scripts/prepare-core-context.sh          # or: make core-context

# 2. Build the image from that context (not from this repository)
make docker                              # -> streamline:dev

# 3. Run it
STREAMLINE_IMAGE=streamline:dev docker compose up -d
curl http://localhost:9094/health
```

Step 1 fails until a maintainer pins a 40-character core commit SHA in
`core-source.env`. That is the fail-closed behaviour, not a bug: an image built
from "whatever is on a branch tip" cannot be identified afterwards.

For the demo stack with persistent volumes and auto-seeded data:

```bash
STREAMLINE_IMAGE=streamline:dev docker compose -f docker-compose.demo.yml up -d
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  Clients                          │
│  (Kafka clients, SDKs, CLI, Web UI)              │
└──────────────────┬───────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │   :9092 (Kafka)     │
        │   :9094 (HTTP API)  │
        ├─────────────────────┤
        │   Streamline Pod    │
        │   (StatefulSet)     │
        ├─────────────────────┤
        │   PVC (/data)       │
        └─────────────────────┘
```

## Contents

- `helm/` — Helm chart for Streamline
- `k8s/` — Raw Kubernetes manifests & Kustomize overlays
- `docker/` — Docker-related configurations
- `Dockerfile` — Official Streamline image (built from Streamline **core** sources)
- `Dockerfile.edge` — Unsupported reference only; nothing builds, publishes or runs it
- `core-source.env` — Immutable core commit the official image is built from
- `scripts/prepare-core-context.sh` — Materialises that core checkout
- `monitoring/METRICS.md` — Metric contract and verification status
- `docker-compose*.yml` — Docker Compose stacks for various scenarios

## Building the Official Image

This repository holds deployment artifacts only — it contains no Streamline
core sources. The image is therefore built from a checkout of the core
repository at the commit pinned in `core-source.env`:

```bash
# Check out the pinned core sources into .build/core, then build
make docker

# Full edition (SASL auth, clustering); TLS is in every build
make docker STREAMLINE_EDITION=full STREAMLINE_FEATURES=full

# Smoke-test the locally built image
make smoke-test STREAMLINE_IMAGE=streamline:dev
```

### Editions

The build arguments are a capability contract, enforced in the Dockerfile:

| `STREAMLINE_EDITION` | `STREAMLINE_FEATURES` | `STREAMLINE_CAPABILITIES` | Chart may enable |
|----------------------|-----------------------|---------------------------|------------------|
| `standard` | must be empty | must be empty | TLS only (it is compiled into every build) |
| `full` | exactly `full` (core's meta-feature) | must be empty | TLS, SASL auth, clustering* |
| `custom` | any other list, e.g. `cdc,analytics` | **required**: `auth`, `clustering`, `moonshot` or `none` | exactly what you declare |

\* clustering is advertised by the image but still rejected by the chart until
peer bootstrap exists.

`full` used to accept any feature list, which minted images labelled "full" that
cargo had never compiled auth into. An arbitrary list is now a `custom` build
and must say what it supports; the declaration is recorded in the
`dev.streamline.capabilities` label and is what the chart's `image.capabilities`
must mirror. The chart never infers capabilities for a custom image.

```bash
make docker STREAMLINE_EDITION=custom STREAMLINE_FEATURES=cdc,analytics \
  STREAMLINE_CAPABILITIES=none STREAMLINE_IMAGE=streamline-cdc:dev
```

Image publishing is owned exclusively by `.github/workflows/docker-publish.yml`;
no other workflow pushes tags. It pushes a staging reference first, validates
that digest (smoke test, vulnerability scan, SBOM, signature, attestations) and
only then promotes the same digest to the public tags. Promotion and SLSA
provenance require a release-tag **push**; a manual `workflow_dispatch`,
including one with a `core_ref` override or an existing tag selected as its
ref, is validation-only and cannot create public tags.

The playground image compiles core too, so it uses the same prepared context
(`scripts/prepare-core-context.sh` also overlays this repository's image assets
under `.deploy/`):

```bash
scripts/prepare-core-context.sh
docker build -f playground/Dockerfile .build/core \
  --build-arg STREAMLINE_CORE_REF="$(scripts/prepare-core-context.sh --print-ref)" \
  -t streamline-playground:dev
```

It is not published either: the publisher builds `Dockerfile` only.
`Dockerfile.edge` exists as an **unsupported reference** and is not built by
anything — see [Edge appliance (unsupported)](#edge-appliance-unsupported).

### Release gates

`make static` runs the hermetic gates that keep the claims in this repository
honest — build context, single publisher, publish ordering and digest identity,
core-pin fail-closed behaviour, image editions, TLS scope, fixed listener ports,
OCI image-reference normalization, published-artifact claims, disabled demos
and the metric contract.

While `core-source.env` carries no commit, CI's `image-build` job **fails**. It
resolves the pin unconditionally and nothing in it is guarded by `if:`,
`continue-on-error` or `|| true`, so an unbuildable repository cannot report a
green image gate (`tests/core-pin-gate_test.sh`).

## Quick Start

### Docker

```bash
# Build an image first (see "Building the Official Image"); nothing is published
make docker                                    # -> streamline:dev

# Start Streamline
STREAMLINE_IMAGE=streamline:dev docker compose up -d

# Verify it's running
curl http://localhost:9094/health

# Start with demo topics and sample data
STREAMLINE_IMAGE=streamline:dev docker compose -f docker-compose.demo.yml up -d
```

Without `STREAMLINE_IMAGE`, `docker compose up` stops on the placeholder tag
`streamline:set-STREAMLINE_IMAGE`, which exists in no registry. `docker compose
config` still parses every stack, so validation never needs a pull.

### Quick Start with Demo Data

The demo compose file starts Streamline in playground mode and automatically seeds
four demo topics with realistic sample data (events, logs, metrics, and orders):

```bash
# Start with pre-seeded demo data (STREAMLINE_IMAGE names an image you built)
export STREAMLINE_IMAGE=streamline:dev
docker compose -f docker-compose.demo.yml up -d

# Verify demo topics
docker compose -f docker-compose.demo.yml exec streamline streamline-cli topics list

# Consume sample events
docker compose -f docker-compose.demo.yml exec streamline \
  streamline-cli --broker localhost:9092 consume demo-events --from-beginning -n 5

# Consume order records
docker compose -f docker-compose.demo.yml exec streamline \
  streamline-cli --broker localhost:9092 consume demo-orders --from-beginning -n 5

# Check server health
curl http://localhost:9094/health

# Tear down (data persists in volume)
docker compose -f docker-compose.demo.yml down

# Tear down and remove all data
docker compose -f docker-compose.demo.yml down -v
```

**Demo topics seeded:**

| Topic | Description | Messages |
|-------|-------------|----------|
| `demo-events` | User activity events (signups, logins, page views) | 10 |
| `demo-logs` | Application log lines (INFO, WARN, ERROR) | 10 |
| `demo-metrics` | System metrics (CPU, memory, HTTP latency) | 10 |
| `demo-orders` | E-commerce order lifecycle records | 10 |

### Helm

The chart ships **no default image tag**: no image is published, so a default
would render every workload against a manifest nobody pushed. Name an image you
built and pushed where the cluster can pull it:

```bash
helm install streamline ./helm/streamline \
  --set image.repository=my-registry/streamline \
  --set image.tag=<tag>

# Install with custom values
helm install streamline ./helm/streamline \
  --set image.repository=my-registry/streamline --set image.tag=<tag> \
  --set persistence.size=50Gi \
  --set resources.limits.memory=2Gi
```

Without them the render fails with an explanation, instead of installing a
workload that lands in `ImagePullBackOff`.

### Kubernetes (raw manifests)

The base carries the unpullable placeholder `streamline:set-image-before-apply`
for the same reason. Build and push an image (see
[`k8s/README.md`](k8s/README.md)), then:

```bash
cd k8s
kustomize edit set image streamline=my-registry/streamline:<tag>
kubectl apply -k .
```

## Helm Chart Values

Key configuration values for the Streamline Helm chart (`helm/streamline/values.yaml`):

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas; values greater than 1 are rejected until peer bootstrap exists | `1` |
| `image.repository` | Container image repository | `ghcr.io/streamlinelabs/streamline` |
| `image.tag` | Container image tag. **Required** — empty fails the render, because no image is published | `""` |
| `image.edition` | Image edition: `standard`, `full` or `custom` (see [Editions](#editions)) | `full` |
| `image.capabilities` | Capability declaration for a `custom` image; required there, rejected elsewhere | `[]` |
| `config.logLevel` | Server log level | `info` |
| `config.dataDir` | Data directory path | `/data` |
| `config.kafkaAddr` | Kafka protocol listen address. The port is **fixed at 9092**; other values are rejected | `0.0.0.0:9092` |
| `config.httpAddr` | HTTP API listen address. The port is **fixed at 9094**; other values are rejected | `0.0.0.0:9094` |
| `config.autoCreateTopics` | Auto-create topics on first produce; always rendered as `STREAMLINE_AUTO_CREATE_TOPICS` because core enables it by default | `false` |
| `config.extraArgs` | Extra CLI arguments appended to the server command (e.g. `--max-message-bytes`) | `[]` |
| `config.clusterEnabled` | Reserved; currently rejected until peer bootstrap is implemented | `false` |
| `autoscaling.enabled` | Reserved; rejected — an HPA would scale the StatefulSet past one broker | `false` |
| `keda.enabled` | Reserved; rejected — a KEDA ScaledObject would scale the StatefulSet past one broker | `false` |
| `tls.enabled` | Enable TLS on the **Kafka listener (9092)**; works with any edition | `false` |
| `tls.existingSecret` | Existing `kubernetes.io/tls` Secret to mount for the Kafka listener | `""` |
| `tls.mountPath` | Where certificate material is mounted | `/etc/streamline/tls` |
| `tls.clientAuth` | Require certificates from **Kafka** clients (mTLS on 9092) | `false` |
| `auth.enabled` | Enable SASL authentication (needs a `full` image) | `false` |
| `auth.existingSecret` | Secret holding the YAML users file — **required** when `auth.enabled` | `""` |
| `auth.usersFileKey` | Key inside `auth.existingSecret` holding the users file | `users.yaml` |
| `auth.mountPath` | Where the users file is mounted read-only | `/etc/streamline/auth` |
| `auth.sasl.mechanisms` | SASL mechanisms to advertise | `[SCRAM-SHA-256]` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.kafkaPort` | Kafka protocol port. **Fixed at 9092**; other values are rejected before render | `9092` |
| `service.httpPort` | HTTP API port. **Fixed at 9094**; other values are rejected before render | `9094` |
| `externalService.enabled` | Enable external LoadBalancer | `false` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.storageClass` | Storage class name | `""` (default) |
| `persistence.size` | PVC size | `10Gi` |
| `resources.requests.memory` | Memory request | `256Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.limits.cpu` | CPU limit | `1000m` |
| `metrics.enabled` | Enable Prometheus metrics | `true` |
| `metrics.serviceMonitor.enabled` | Enable ServiceMonitor CRD | `false` |
| `podDisruptionBudget.enabled` | Enable PDB | `true` |
| `podDisruptionBudget.minAvailable` | Minimum available pods | `1` |
| `terminationGracePeriodSeconds` | Graceful shutdown timeout | `30` |

### Security Defaults

The chart runs with security best practices out of the box:
- Non-root user (UID 1000)
- Read-only root filesystem support
- Dropped capabilities (`ALL`)
- No privilege escalation

### Image Capabilities

SASL authentication requires an image built with the auth feature
(`STREAMLINE_EDITION=full`, i.e. `STREAMLINE_FEATURES=full`). That is what the
publisher builds, so the chart defaults to `image.edition=full`.

The full binary also compiles clustering support, but the chart currently
rejects `config.clusterEnabled=true` and `replicaCount > 1`. It does not yet
render stable node IDs or seed-node bootstrap, so accepting those settings
would create independent brokers rather than a quorum.

TLS is not gated: core compiles it into every build, so `tls.enabled=true` works
with any edition — including a custom `standard` build.

```bash
helm install streamline ./helm/streamline \
  --set image.repository=my-registry/streamline --set image.tag=<tag> \
  --set tls.enabled=true --set tls.existingSecret=streamline-tls
```

For a **custom** build, set `image.edition=custom` and declare what it supports:

```bash
helm install streamline ./helm/streamline \
  --set image.repository=my-registry/streamline --set image.tag=<tag> \
  --set image.edition=custom --set image.capabilities='{auth}'
```

The declaration is mandatory there and rejected on `standard`/`full` (their
capability sets follow from the build). The chart never guesses: a custom image
that declares only `clustering` cannot enable `auth.enabled`, because guessing
"yes" would deploy an unauthenticated broker while the values file says
otherwise.

The experimental moonshot features cannot be configured by this chart at all:
none of the `moonshot.*` settings are rendered into the server configuration, so
switching one on fails the render instead of deploying a server that ignores it.
Listing `moonshot` in `image.capabilities` describes the image, but does not
make those settings take effect.

### Listener ports are fixed

The Kafka listener is **fixed at 9092** and the HTTP API at **9094**. The
container ports, the named ports the probes and Services target, the
NetworkPolicy rules and the metrics wiring are all literal, so a value that
looked like it moved a listener produced a Service pointing at a port nothing
served and probes that never passed. `service.kafkaPort`, `service.httpPort`,
`externalService.kafkaPort`, `config.kafkaAddr`, `config.httpAddr` and
`config.interBrokerPort` are validated by `values.schema.json` before rendering
and again by the chart. Publish a different port *outside* the pod with your own
Service, an ingress, or `kubectl port-forward`.

### TLS scope

The chart's TLS settings protect the **Kafka protocol listener (9092)** only.
The HTTP API on 9094 — health, metrics, management — keeps serving plaintext
HTTP, which is how the chart's own probes reach it, and `tls.clientAuth` is
mutual TLS for Kafka clients: nothing here asks an HTTP client for a
certificate. Serve the HTTP API over TLS by terminating it in front of the
Service (the chart's `ingress.tls` list, a reverse proxy or a service mesh).

### SASL Authentication

Streamline core authenticates against a YAML users file containing precomputed
password hashes / SCRAM credentials, and never reads credentials from the
environment. `auth.enabled=true` therefore requires `auth.existingSecret`
holding that file; inline `auth.sasl.username` / `auth.sasl.password` are
rejected at render time instead of being silently dropped. See
[`helm/README.md`](helm/README.md#enable-sasl-authentication-with-an-existing-secret).

### Monitoring Caveat

Dashboard and alert queries reference `streamline_*` metric names that have not
been verified against the metrics Streamline core emits. See
[`monitoring/METRICS.md`](monitoring/METRICS.md) before relying on them.

## Docker Compose Variants

| File | Description | Status |
|------|-------------|--------|
| `docker-compose.yml` | Standard single-node deployment | Needs `STREAMLINE_IMAGE` |
| `docker-compose.demo.yml` | All-in-one demo with pre-seeded topics and sample data | Needs `STREAMLINE_IMAGE` |
| `docker-compose.kafka-clients.yml` | Multi-language Kafka client compatibility demo | Needs `STREAMLINE_IMAGE` |
| `docker-compose.test.yml` | Smoke test (`make smoke-test`) — also the publisher's release gate | Needs `STREAMLINE_IMAGE` |
| `docker-compose.conformance.yml` | SDK conformance server | Needs `STREAMLINE_IMAGE` (full edition) |
| `docker-compose.jepsen.yml` | Correctness harness; multi-node operation is **unsupported** by these artifacts | Needs `STREAMLINE_IMAGE` |
| `docker-compose.moonshot-demo.yml` | Moonshot feature demo; needs an image you build with those features | Needs `STREAMLINE_MOONSHOT_IMAGE` |
| `docker-compose.cdc-demo.yml` | CDC pipeline demo — **disabled**, see below | Starts nothing |

No stack has a runnable default image, because no image is published. Each one
falls back to a local-only placeholder that matches nothing in any registry, so
`up` stops with a pull error naming the variable to set instead of pretending a
release exists.

`make compose-config` (part of `make test`) validates that every stack parses;
it pulls nothing and starts nothing, and it stops at the first invalid file.

### Feature-Gated Demos

Streamline core takes its optional capabilities as **compile-time** cargo
features. Core reads no `STREAMLINE_FEATURES` variable, so putting one in a
container's environment enables nothing, and no published tag can be assumed to
carry them. `tests/feature-gated-demos_test.sh` (part of `make static`) fails if
any stack sets a runtime feature variable or gains a runnable default image.

### Moonshot Demo

The moonshot features (semantic topics, agent memory, attestation, branches)
are compile-time cargo features, so `docker-compose.moonshot-demo.yml` has no
runnable default image and fails closed until you supply one built from the
pinned core commit:

```bash
make docker STREAMLINE_EDITION=custom STREAMLINE_FEATURES=moonshot \
  STREAMLINE_CAPABILITIES=moonshot STREAMLINE_IMAGE=streamline-moonshot:dev

STREAMLINE_MOONSHOT_IMAGE=streamline-moonshot:dev \
  docker compose -f docker-compose.moonshot-demo.yml up
```

Pass whichever feature name(s) your core checkout defines: cargo fails the
build on an unknown feature, so the image either contains them or is never
built. Without `STREAMLINE_MOONSHOT_IMAGE`, `docker compose up` stops on a
placeholder tag that exists in no registry rather than starting a stock server
that lacks every feature the demo shows.

### CDC Demo (disabled)

`docker-compose.cdc-demo.yml` is **disabled** and starts nothing. Its pipeline
is unverified end to end: the CDC source-registration route, the request body in
`cdc-demo/cdc-source.json`, the start route, the message-read path and the
StreamQL endpoint were taken from documentation, not from a server anyone ran
here — and nothing in this repository can tell you whether they answer or 404.
CDC and analytics are also compile-time features that no published image is
built with.

Every service sits behind the `disabled` Compose profile and the entry point
fails closed:

```bash
./demos/cdc-demo.sh     # exits non-zero and explains why
```

Re-enabling it means, in order: building an image with the `cdc` and
`analytics` features from the pinned core commit, capturing the routes and
payloads that server really accepts, adding a test that asserts rows reach a
topic, and only then dropping the profile
(`tests/cdc-demo-disabled_test.sh` holds that line).

### Edge appliance (unsupported)

There is no runnable edge surface. The MQTT bridge on `:1883`, store-and-forward
and cloud sync are unverified claims about core: no smoke test, conformance run
or published image exercises any of them, and no `streamline-edge` tag has ever
been built or pushed. The compose stack and the pilot demo that drove them have
been removed rather than left pointing at listeners nothing opens;
`demos/edge-pilot.sh` now exits non-zero without touching Docker.

`Dockerfile.edge` is kept as an **unsupported source reference**: it is not
built, published or tested, it no longer exposes 1883, and the bundled
`docker/edge/streamline-edge.toml` ships its `[edge]` and `[mqtt]` sections
disabled. `tests/edge-unsupported_test.sh` keeps it that way.

## License

Apache-2.0
