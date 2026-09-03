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

### Added
- `STREAMLINE_CAPABILITIES` build arg and `dev.streamline.capabilities` image
  label: a `custom` edition must declare what it supports, and the Helm chart's
  `image.capabilities` mirrors that declaration.
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
- The retained future-release logic in `scripts/install.sh` filters the
  requested libc *before* resolving uniqueness. A musl-only release cannot
  satisfy a GNU request, and checksum verification remains mandatory.
- `docker-publish.yml` is the single image publisher; it runs on release tags
  only, serializes with a concurrency group and no longer publishes `latest`
  from branch pushes.
- `scripts/install.sh` now fails before any download or filesystem mutation
  because no controlled installer endpoint or verified release archive set
  exists. Its retained release-resolution logic still requires SHA-256
  verification and has no bypass flag.
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

### Removed
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
- `scripts/prepare-core-context.sh --help` derived its output from a hard-coded
  line range and silently truncated the option list when the header grew.


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
