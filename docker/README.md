# Streamline

**The Redis of Streaming** — A Kafka protocol-compatible, single-binary streaming platform (<50MB, zero config).

## Status: no image is published yet

No Streamline image exists in any registry. The image is built from the core
commit pinned in `core-source.env`, which does not name one yet, so the single
publisher (`.github/workflows/docker-publish.yml`) has never pushed a tag. Build
one yourself first:

```bash
scripts/prepare-core-context.sh          # materialises .build/core
make docker                              # -> streamline:dev
```

## Quick Start

```bash
docker run -d --name streamline \
  -p 9092:9092 \
  -p 9094:9094 \
  -v streamline_data:/data \
  streamline:dev
```

Verify it's running:

```bash
curl http://localhost:9094/health
```

Connect with any Kafka client on `localhost:9092`.

## Tag scheme (once images are published)

The publisher writes these tags — and only after a staged digest has passed the
smoke test, vulnerability scan, SBOM generation, signing and attestation. The
same digest is then promoted to every tag below, so they are copies of validated
bits rather than fresh builds.

| Tag | Description |
|-----|-------------|
| `x.y` (e.g. `0.3`) | Latest patch for a minor version |
| `core-<sha>` | The exact Streamline core commit the image was built from |
| `latest` | Most recent non-prerelease release; mutable, unsuitable for pinning |
| `staging-<run>-<attempt>` | Internal build artefact, never referenced by a deployment |

## Ports

- **9092** — Kafka protocol (produce, consume, admin)
- **9094** — HTTP API (health checks, metrics, management)

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STREAMLINE_LISTEN_ADDR` | Kafka listen address | `0.0.0.0:9092` |
| `STREAMLINE_DATA_DIR` | Data directory | `/data` |
| `STREAMLINE_LOG_LEVEL` | Log level | `info` |

## Image Editions

| Label | Value | Meaning |
|-------|-------|---------|
| `dev.streamline.edition` | `standard` | Default cargo features. TLS is compiled in; SASL auth and clustering are not |
| `dev.streamline.edition` | `full` | Built with `STREAMLINE_FEATURES=full` exactly — core's meta-feature, which is what makes "auth + clustering" a knowable claim |
| `dev.streamline.edition` | `custom` | An arbitrary feature list. Nothing is implied: the build must declare `dev.streamline.capabilities` |
| `dev.streamline.features` | e.g. `full`, `cdc,analytics` | The cargo features the binary was compiled with |
| `dev.streamline.capabilities` | e.g. `auth`, `none` | What a `custom` build declares it supports; empty for `standard`/`full`, whose capabilities follow from the edition |
| `org.opencontainers.image.revision` | commit SHA | The Streamline core commit the image was built from |

The Helm chart reads the same contract: `image.edition=custom` requires an
explicit `image.capabilities` list mirroring the label, and never infers auth or
clustering from a custom build.

Inspect an image before deploying:

```bash
docker inspect --format '{{ index .Config.Labels "dev.streamline.edition" }}' \
  streamline:dev
docker inspect --format '{{ index .Config.Labels "dev.streamline.capabilities" }}' \
  streamline:dev
```

## TLS

The server's TLS settings cover the **Kafka listener (9092)** only. The HTTP API
on 9094 serves plaintext HTTP; put an ingress, reverse proxy or service mesh in
front of it if that traffic must be encrypted.

## Links

- [Documentation](https://github.com/streamlinelabs/streamline-docs)
- [Source Code](https://github.com/streamlinelabs/streamline)
- [Deployment Artifacts](https://github.com/streamlinelabs/streamline-deploy)
- [GitHub Container Registry](https://ghcr.io/streamlinelabs/streamline)

## License

Apache-2.0
