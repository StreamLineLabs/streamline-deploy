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
- `core-source.env` and `scripts/prepare-core-context.sh`: the official image is
  built from an explicitly checked-out, immutable Streamline core commit instead
  of assuming core sources exist in this repository.
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

### Fixed
- `scripts/install.sh` resolves Linux releases that publish both a glibc and a
  musl archive deterministically (glibc by default, `--libc musl` /
  `STREAMLINE_LIBC=musl` to switch). Genuine ambiguity still fails closed.
- `docker-publish.yml` passes the `core_ref` dispatch input through `env:`
  instead of interpolating it into a `run:` script, where a value containing
  shell metacharacters would have executed as code. A static gate in
  `tests/workflow-publisher_test.sh` keeps it that way.
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
