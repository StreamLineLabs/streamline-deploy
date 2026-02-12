# Streamline

**The Redis of Streaming** — A Kafka protocol-compatible, single-binary streaming platform (<50MB, zero config).

## Quick Start

```bash
docker run -d --name streamline \
  -p 9092:9092 \
  -p 9094:9094 \
  -v streamline_data:/data \
  streamlinelabs/streamline:latest
```

Verify it's running:

```bash
curl http://localhost:9094/health
```

Connect with any Kafka client on `localhost:9092`.

## Available Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable release |
| `x.y.z` (e.g. `0.2.0`) | Specific version |
| `x.y` (e.g. `0.2`) | Latest patch for a minor version |

## Ports

- **9092** — Kafka protocol (produce, consume, admin)
- **9094** — HTTP API (health checks, metrics, management)

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STREAMLINE_LISTEN_ADDR` | Kafka listen address | `0.0.0.0:9092` |
| `STREAMLINE_DATA_DIR` | Data directory | `/data` |
| `STREAMLINE_LOG_LEVEL` | Log level | `info` |

## Links

- [Documentation](https://github.com/streamlinelabs/streamline-docs)
- [Source Code](https://github.com/streamlinelabs/streamline)
- [Deployment Artifacts](https://github.com/streamlinelabs/streamline-deploy)
- [GitHub Container Registry](https://ghcr.io/streamlinelabs/streamline)

## License

Apache-2.0
