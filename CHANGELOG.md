# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Changed
- OCI image policy checks now parse explicit registry ports as bounded decimal
  values, normalize leading-zero spellings for comparison, reject ports outside
  `1..=65535`, and preserve the original reference for emission and diagnostics.
- Restrict official image publication to `linux/amd64` until every additional
  architecture has its own pre-promotion smoke and vulnerability scan lane;
  an unvalidated arm64 manifest is no longer promoted under public tags.
- Correct the disabled moonshot demo's build instructions to use the `custom`
  edition with explicit `moonshot` capabilities, matching the Dockerfile guard.

### Added
- Release gates for the governance review: `tests/core-pin-gate_test.sh`,
  `tests/publish-pipeline_test.sh`, `tests/published-artifacts_test.sh`,
  `tests/image-editions_test.sh`, `tests/tls-scope_test.sh`,
  `tests/listener-ports_test.sh`, `tests/playground-image_test.sh`,
  `tests/edge-unsupported_test.sh` and `tests/cdc-demo-disabled_test.sh`, all
  wired into `make static` (and individually runnable as make targets). They are
  hermetic: text/JSON inspection plus this repository's own scripts, with no
  cluster, registry, network or docker.
- `STREAMLINE_CAPABILITIES` build arg and `dev.streamline.capabilities` image
  label: a `custom` edition must declare what it supports, and the Helm chart's
  `image.capabilities` mirrors that declaration.
- `demos/cdc-demo.sh`: the documented entry point for the CDC demo, which exits
  non-zero and explains why the pipeline is disabled.
- `cdc-demo/README.md`: records that `cdc-source.json` is an unverified shape
  sketch rather than a working request body.
- `helm/streamline/tests/values/test-image.yaml`: the explicit image every chart
  unit test now names, because the chart ships no default tag.
- `core-source.env` and `scripts/prepare-core-context.sh`: the official image is
  built from an explicitly checked-out, immutable Streamline core commit instead
  of assuming core sources exist in this repository.
- Image editions (`STREAMLINE_EDITION` / `STREAMLINE_FEATURES` build args and
  `dev.streamline.*` labels) plus chart-side capability gating: enabling auth or
  clustering against an image that does not support them now fails the Helm
  render.
- TLS and SASL wiring: certificate Secrets are mounted into the workload;
  `tls.existingSecret` is honoured and `auth.existingSecret` supplies the users
  file the server authenticates against.
- `auth.usersFileKey` and `auth.mountPath` name the key inside
  `auth.existingSecret` that holds the YAML users file and where it is mounted.
- Release gates: image build + smoke test in CI, `make static` (build-context,
  single-publisher and metric-contract checks) and characterization tests for
  the installer and the core-context script.
- `make compose-config` validates that every Compose stack parses, without
  pulling or running anything, and stops at the first invalid file. Wired into
  `make test`; `tests/makefile-compose-gate_test.sh` and
  `tests/moonshot-demo_test.sh` join `make static`.
- `tests/feature-gated-demos_test.sh` (`make feature-demo-claims`, part of
  `make static`): a hermetic gate that fails if any `docker-compose*.yml` sets a
  runtime feature variable, and that holds every feature-gated demo (CDC,
  moonshot, edge) to an explicitly supplied image with a local-only default and
  a documented build, cross-checked against the Dockerfile that produces it.
- `monitoring/METRICS.md`: metric contract recording that every `streamline_*`
  name used by dashboards and alerts is unverified against core.
- `release.yml` packages and checksums the Helm chart as a workflow artifact
  (no external publication).

### Changed
- **CI's image gate fails while `core-source.env` is unpinned, instead of
  skipping.** The `image-build` job used to swallow the resolver's exit status
  (`2>/dev/null`), set `pinned=false`, emit a `::notice::` and guard every
  following step with `if: steps.core.outputs.pinned == 'true'` — a green gate
  claiming the pinned tree still builds and smoke-tests, neither of which was
  evaluated. The resolver now runs unconditionally under `set -euo pipefail` and
  no step is conditional, so the job is RED until a maintainer pins a
  40-character core commit SHA (`tests/core-pin-gate_test.sh`).
- **`docker-publish.yml` validates before it publishes.** It used to push
  `{{version}}`, `{{major}}.{{minor}}` and `latest` in the first step and run the
  smoke test, scan, SBOM and signature afterwards — opinions about bits users
  could already pull. It now pushes one staging reference
  (`:staging-<run>-<attempt>`), pins the resulting digest, and runs every
  validation against that digest (strict smoke test, Trivy CRITICAL/HIGH with
  `exit-code: 1`, cosign signature, SBOM and SBOM/provenance attestations). A
  separate `promote` job — gated by `needs:` — then copies that exact digest onto
  the public tags with `imagetools create` and verifies each tag resolves back to
  it. `docker/metadata-action` runs at promotion time only
  (`tests/publish-pipeline_test.sh`).
- `docker-compose.test.yml` asserts instead of hoping: `topics create` no longer
  ends in `|| true`, the created topic must appear in `topics list`, the produce
  and consume assertions must both execute, and the health wait is bounded so a
  server that never starts fails the run rather than hanging it.
- **Nothing presents an unpublished artifact as installable.** No image or chart
  has ever been pushed, yet the artifacts told readers to `docker pull
  ghcr.io/streamlinelabs/streamline:0.3.0`, defaulted every Compose stack to it,
  pinned it in the raw manifests and shipped it as the chart's `image.tag`. Every
  Compose stack now takes its Streamline image from a variable with a local-only,
  unpullable default; `k8s/` carries `streamline:set-image-before-apply`; the
  chart ships `image.tag: ""` and fails the render with an explanation; and the
  READMEs lead with a source build from the pinned core context. No version
  string was changed (`tests/published-artifacts_test.sh`).
- **`STREAMLINE_EDITION=full` accepts only `STREAMLINE_FEATURES=full`.** Any
  non-empty list used to be accepted, minting images labelled `full` that cargo
  had never compiled auth into while the chart happily rendered an authenticated
  configuration onto them. Arbitrary lists are now `STREAMLINE_EDITION=custom`
  and must declare `STREAMLINE_CAPABILITIES` (`auth`, `clustering`, `moonshot` or
  `none`). The chart follows: `image.capabilities` is required for `custom`,
  rejected for `standard`/`full`, and no capability is ever inferred for a custom
  build (`tests/image-editions_test.sh`, which executes the Dockerfile guard).
- **TLS is documented as Kafka-only.** The chart's TLS settings configure the
  Kafka protocol listener (9092); the HTTP API on 9094 keeps serving plaintext
  HTTP — the probes reach it that way — and nothing asks an HTTP client for a
  certificate. The docs claimed "TLS on both Kafka and HTTP ports" and described
  the Secret as securing the API. Templates and environment variables are
  unchanged and now explicitly named as Kafka TLS; HTTPS for the HTTP API is an
  ingress/reverse-proxy concern (`tests/tls-scope_test.sh`).
- **Listener ports are fixed at 9092/9094.** `service.kafkaPort`,
  `service.httpPort`, `externalService.kafkaPort`, `config.kafkaAddr`,
  `config.httpAddr` and `config.interBrokerPort` looked adjustable but reached
  only some of the wiring, so a custom value produced a Service pointing at a
  port nothing served and probes aimed at the old one. They are now rejected by
  `values.schema.json` before render and again by the chart, and
  `networkPolicy.ingress` may only name ports the workload serves
  (`tests/listener-ports_test.sh`).
- `playground/Dockerfile` creates and chowns `/data` before dropping to UID 1000
  and sets `STREAMLINE_DATA_DIR=/data`, with an explicit `CMD` naming that
  directory. A non-root container cannot create it at run time, so any write
  killed the container with a permission error
  (`tests/playground-image_test.sh`).
- The retained future-release logic in `scripts/install.sh` filters the
  requested libc *before* resolving uniqueness. A musl-only release cannot
  satisfy a GNU request, and checksum verification remains mandatory.
- `k8s/README.md` documents the real build: prepare the pinned core context
  (`scripts/prepare-core-context.sh` / `make core-context`) and run
  `docker build -f Dockerfile .build/core`. `docker build -t … .` from this
  repository has never worked — there are no Rust sources here — and
  `tests/dockerfile-context_test.sh` now sweeps the docs for that instruction.
- `helm lint` (Makefile and `release.yml`) and the chart unit tests pass an
  explicit test image, since the chart refuses to render without one.
- `make smoke-test-published` became `make smoke-test-image`: there is no
  published image to smoke-test, so the target requires `STREAMLINE_IMAGE`.
- `docker-publish.yml` is the single image publisher; it runs on release tags
  only, serializes with a concurrency group and no longer publishes `latest`
  from branch pushes.
- `scripts/install.sh` now fails before any download or filesystem mutation
  because no controlled installer endpoint or verified release archive set
  exists. Its retained release-resolution logic still requires SHA-256
  verification and has no bypass flag.
- Compose stacks and Kubernetes manifests reference pinned image tags.
- TLS is no longer capability-gated: Streamline core compiles it into every
  build, so `tls.enabled` works with any edition, including a custom `standard`
  build. `"tls"` inside `image.capabilities` is accepted and ignored.
- The `full` edition advertises `auth` and `clustering`. The experimental
  moonshot feature set is advertised by no edition and cannot be configured by
  this chart at all; `image.capabilities: [moonshot]` only describes the image.
- `image.edition` now defaults to `full`, matching the image the official
  publisher builds and the tag the chart pins by default.
- Clustered and multi-replica Helm renders now fail explicitly until the chart
  can configure stable node IDs and seed peers; it no longer creates
  independent brokers that look like a quorum.
- `autoscaling.enabled` and `keda.enabled` now fail the Helm render for the same
  reason. Both created an autoscaler that raises the StatefulSet's replica count
  after install, bypassing the `replicaCount > 1` guard and starting independent
  brokers with their own data. The values keys, `hpa.yaml` and
  `keda-scaledobject.yaml` are kept to document the intended shape once
  clustered mode exists.
- `k8s/configmap.yaml` sets `STREAMLINE_AUTO_CREATE_TOPICS: "false"`
  explicitly: Streamline core enables auto topic creation by default, so
  omitting the key deployed a broker that created topics on first produce.
- `k8s/statefulset.yaml`, `k8s/pod-disruption-budget.yaml` and `k8s/README.md`
  no longer tell operators to scale the standalone broker to three replicas or
  describe the deployment as highly available; the manifests deploy one broker
  and the PDB only limits voluntary disruptions.
- `k8s/keda/` is marked `UNSUPPORTED EXAMPLE — DO NOT APPLY` and documented as
  such in `k8s/README.md`. It stays out of `k8s/kustomization.yaml`, so
  `kubectl apply -k k8s/` never creates it.
- `tests/scaling-claims_test.sh` (new, hermetic; wired into `make static`)
  fails when the raw ConfigMap omits `STREAMLINE_AUTO_CREATE_TOPICS`, when an
  artifact recommends more than one broker without marking it unsupported, when
  a chart autoscaler guard is removed, or when the KEDA example loses its
  unsupported marker.

### Removed
- `docker-compose.edge.yml` and the runnable edge pilot. The MQTT bridge on
  `:1883`, store-and-forward and cloud sync are unverified against core — no
  smoke test, conformance run or published image exercises them — and no
  `streamline-edge` tag has ever been built or pushed. `demos/edge-pilot.sh` now
  exits non-zero without touching Docker, `Dockerfile.edge` is an explicitly
  unsupported source reference that no longer exposes 1883, and
  `docker/edge/streamline-edge.toml` ships its `[edge]` and `[mqtt]` sections
  disabled (`tests/edge-unsupported_test.sh`).
- The runnable CDC demo. Its source-registration route, request body, start
  route, message-read path and StreamQL endpoint came from documentation rather
  than from a server anyone ran here, and `cdc`/`analytics` are compile-time
  features no published image is built with. Every service in
  `docker-compose.cdc-demo.yml` now sits behind the `disabled` Compose profile,
  the image default is an unpullable placeholder, and no artifact may present
  `/api/v1/cdc/sources` or `/sql` as a runnable instruction
  (`tests/cdc-demo-disabled_test.sh`).
- `auth.sasl.username`, `auth.sasl.password`, `auth.usernameKey`,
  `auth.passwordKey` and `auth.extraSecrets`. Streamline core authenticates
  against a YAML users file containing precomputed hashes / SCRAM credentials,
  which the chart cannot derive from a plaintext value; the chart no longer
  generates an auth Secret. `auth.enabled=true` now requires
  `auth.existingSecret`, and the removed settings fail the render with a
  migration hint rather than being silently ignored.
- `auth.sasl.mechanism` (singular) in favour of the `auth.sasl.mechanisms` list
  that maps onto `STREAMLINE_AUTH_SASL_MECHANISMS`.
- `tls.mutualTls`, `tls.certSecretName`, `tls.certFile`, `tls.keyFile` and
  `tls.caFile`. None was read by any template, so `mutualTls: true` advertised
  mutual TLS while the workload accepted unauthenticated clients. They now fail
  the render pointing at `tls.clientAuth`, `tls.existingSecret` and
  `tls.mountPath`.
- Top-level `extraArgs`, superseded by `config.extraArgs`. A leftover top-level
  value is rejected instead of being dropped without a word.

### Fixed
- `config.autoCreateTopics: false` now reaches the server:
  `STREAMLINE_AUTO_CREATE_TOPICS` is always rendered as `"true"` or `"false"`.
  The variable used to be omitted when the value was `false`, leaving core at
  its own default (auto-creation on) while the values file said otherwise.
- Moonshot settings are rejected outright instead of being accepted and dropped.
  No template renders `moonshot.*` into the ConfigMap or the container
  arguments, so a render that "succeeded" because the image declared the
  `moonshot` capability deployed a server that ignored every one of those
  settings. Any `moonshot.*.enabled: true` now fails the render, and
  `image.capabilities: [moonshot]` no longer implies the chart can configure
  them.
- The `docker-compose.yml` header referenced a Docker Hub image that no workflow
  publishes; it now names the `ghcr.io` tags the single publisher pushes
  (`tests/workflow-publisher_test.sh` gates this).
- `docker-compose.moonshot-demo.yml` no longer advertises features its image
  cannot have. It defaulted to the published tag while claiming a "full-edition
  image built with the moonshot features" supplied them, and set
  `STREAMLINE_FEATURES` in the container environment. The publisher builds
  `STREAMLINE_FEATURES=full` (SASL auth and clustering), the moonshot features
  are compile-time cargo features, and core reads no `STREAMLINE_FEATURES`
  variable — so `docker compose up` started a stock server with none of the
  advertised features and nothing said so. The stack now fails closed: both
  services take `${STREAMLINE_MOONSHOT_IMAGE}`, whose default is a local-only
  placeholder tag that exists in no registry, the runtime feature variable is
  gone, and the header documents building the image with
  `--build-arg STREAMLINE_FEATURES=moonshot` from the pinned core context.
  `docker compose config` stays valid with no environment set, so
  `make compose-config` still validates the stack without pulling or running
  anything (`tests/moonshot-demo_test.sh` gates this).
- `docker-compose.cdc-demo.yml` no longer advertises features its image cannot
  have, for the same reason. It defaulted to the published tag and set
  `STREAMLINE_FEATURES=cdc,analytics` in the container environment; core reads
  no such variable and `cdc`/`analytics` are compile-time cargo features, so
  `docker compose up` started a stock server whose `/api/v1/cdc/sources` and
  `/sql` endpoints — the whole demo — do not exist, and nothing said so. The
  stack now fails closed: the Streamline service takes
  `${STREAMLINE_CDC_IMAGE}`, whose default is a local-only placeholder tag that
  exists in no registry, the runtime feature variable is gone, and the header
  documents building the image with `--build-arg STREAMLINE_FEATURES=cdc,analytics`
  from the pinned core context. `docker compose config` stays valid with no
  environment set (`tests/feature-gated-demos_test.sh` gates this).
- `docker-compose.edge.yml` no longer defaults to an image nobody publishes. It
  declared "this stack runs a published image" and defaulted to
  `ghcr.io/streamlinelabs/streamline-edge:0.3.0`, but the single publisher
  (`.github/workflows/docker-publish.yml`) builds `Dockerfile` and pushes
  `ghcr.io/streamlinelabs/streamline` only — no workflow has ever built or
  pushed an edge tag, so `docker compose up` and `demos/edge-pilot.sh` failed on
  an unresolvable manifest while the file promised a supported image. The stack
  now fails closed on the same contract as the CDC and moonshot demos: the
  appliance takes `${STREAMLINE_EDGE_IMAGE}`, whose default is a local-only
  placeholder tag that exists in no registry, and the header documents the real
  build — `scripts/prepare-core-context.sh` plus
  `docker build -f Dockerfile.edge .build/core` — including that
  `Dockerfile.edge` takes no `STREAMLINE_FEATURES` build arg because it compiles
  the fixed `compression,edge` cargo features. `demos/edge-pilot.sh` now refuses
  to start without the variable and prints the build instead.
  `tests/feature-gated-demos_test.sh` gained an `edge` row, so a registry
  default or a runtime feature claim in this stack fails `make static`; the
  table now also cross-checks each demo's feature list against the Dockerfile
  that builds it, so a row cannot document a build flag that does not exist.
- `make test` validated every `docker-compose*.yml` in a shell `for` loop
  without `|| exit 1`. A loop reports the status of its last iteration only, so
  an invalid stack anywhere but the alphabetically last file left `make test`
  green — `docker-compose.cdc-demo.yml` through `docker-compose.kafka-clients.yml`
  could all have been broken without CI noticing. The loop moved into a
  `compose-config` target that stops at the first invalid file, and
  `tests/makefile-compose-gate_test.sh` evaluates the recipe from the Makefile
  itself against a stubbed `docker` to prove a non-last failure is no longer
  masked.
- `config.extraArgs` documentation, default examples and tests used the
  non-existent flags `--features` and `--max-message-size`; they now show
  `--max-message-bytes` only.
- Chart TLS settings now use the environment variable names Streamline core
  actually reads: `STREAMLINE_TLS_CERT`, `STREAMLINE_TLS_KEY`,
  `STREAMLINE_TLS_CA_CERT` and `STREAMLINE_TLS_REQUIRE_CLIENT_CERT`. The
  previous `*_FILE` / `_CLIENT_AUTH` names were silently ignored by the server,
  so a release claiming TLS could have served plaintext.
- Chart SASL settings now use `STREAMLINE_AUTH_SASL_MECHANISMS` and
  `STREAMLINE_AUTH_USERS_FILE`. Core does not read credentials from the
  environment, so `STREAMLINE_SASL_USERNAME` / `STREAMLINE_SASL_PASSWORD` were
  never honoured.
- `scripts/install.sh` resolves Linux releases that publish both a glibc and a
  musl archive deterministically (glibc by default, `--libc musl` /
  `STREAMLINE_LIBC=musl` to switch). Genuine ambiguity still fails closed.
- `docker-publish.yml` passes the `core_ref` dispatch input through `env:`
  instead of interpolating it into a `run:` script, where a value containing
  shell metacharacters would have executed as code. A static gate in
  `tests/workflow-publisher_test.sh` keeps it that way.
- `config.extraArgs` is now actually passed to the server (the StatefulSet read
  a non-existent top-level `extraArgs`).
- `scripts/install.sh` no longer falls back to a hard-coded `0.2.0` when the
  latest version cannot be resolved.
- Removed the duplicate, syntactically invalid `docker/Dockerfile.release` and
  the unreferenced `docker/Dockerfile.optimized`.
- `docker-compose.moonshot-demo.yml`: seeder loop variables are escaped for
  Compose interpolation and the CLI targets the server container.
- `Dockerfile.edge` and `playground/Dockerfile` compile Streamline core but
  still copied `Cargo.toml`, `crates/` and `src/` from this repository, which
  has never contained them; `docker-compose.edge.yml` built the edge image with
  `context: .`. Both now build from the prepared core context, fail closed when
  the context is not a core checkout, and build with `--locked`. The edge
  appliance config reaches the context through a namespaced `.deploy/` overlay
  written by `scripts/prepare-core-context.sh`.
- `playground/Dockerfile` declared a `curl` HEALTHCHECK without installing
  `curl`, so the container could only ever report unhealthy. It now installs
  `curl` and runs as the non-root user the other images use.
- `make static` now runs the metric-contract gate it was already documented as
  running.
- `scripts/prepare-core-context.sh --help` derived its output from a hard-coded
  line range and silently truncated the option list when the header grew.
- Documentation drift: supported versions, security contact, chart defaults, and
  the half-merged capability bullet in `CLAUDE.md`.


## [0.3.0] - 2026-04-20

- fix: correct volume mount paths in docker-compose (2026-03-05)
- docs: add deployment troubleshooting guide (2026-03-06)
- chore: update base image to alpine 3.19 (2026-03-06)
- **Documentation**: add monitoring setup instructions
- **Changed**: update monitoring configuration
- **Fixed**: correct volume mount paths in docker-compose
- **Added**: add Grafana dashboard for topic metrics
- **Added**: add Prometheus alerting rules for consumer lag

### Fixed
- Adjust resource limits in production manifest
- Correct volume mount paths in docker-compose

### Changed
- Update base image tag in Dockerfile


## [0.2.0] - 2026-02-18

### Added
- Docker Compose configuration for single-node deployment
- Dockerfile with multi-stage build
- Helm chart for Kubernetes deployment
- Raw Kubernetes manifests with kustomize support
- Health check and readiness probe configurations
- CI pipeline for validating deployment artifacts
- chore: update base Docker image versions
- chore: add liveness probe configuration to Helm templates
- feat: add multi-region Helm chart topology support
- chore: tag Helm chart release candidate 0.3.0-rc1
