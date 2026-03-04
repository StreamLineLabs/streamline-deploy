# Streamline Deploy

[![CI](https://github.com/streamlinelabs/streamline-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/streamlinelabs/streamline-deploy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://docs.docker.com/compose/)
[![Helm](https://img.shields.io/badge/Helm-3.x-0F1689.svg)](https://helm.sh/)

Deployment artifacts for [Streamline](https://github.com/streamlinelabs/streamline) — Helm charts, Kubernetes manifests, and Docker configurations.

## Try It in 10 Seconds

```bash
docker run -p 9092:9092 -p 9094:9094 ghcr.io/streamlinelabs/streamline:latest --playground
```

This starts Streamline in playground mode with four demo topics pre-loaded with sample data. Point any Kafka client at `localhost:9092` and start consuming.

For the full demo with persistent volumes and auto-seeded data, use the [demo compose file](docker-compose.demo.yml):

```bash
docker compose -f docker-compose.demo.yml up -d
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
- `Dockerfile` — Official Streamline Docker image
- `docker-compose*.yml` — Docker Compose stacks for various scenarios

## Quick Start

### Docker

```bash
# Docker Hub
docker pull streamlinelabs/streamline:latest

# GitHub Container Registry
docker pull ghcr.io/streamlinelabs/streamline:latest

# Start Streamline
docker compose up -d

# Verify it's running
curl http://localhost:9094/health

# Start with demo topics and sample data
docker compose -f docker-compose.demo.yml up -d
```

### Quick Start with Demo Data

The demo compose file starts Streamline in playground mode and automatically seeds
four demo topics with realistic sample data (events, logs, metrics, and orders):

```bash
# Start with pre-seeded demo data
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

```bash
# Add and install
helm install streamline ./helm/streamline

# Install with custom values
helm install streamline ./helm/streamline \
  --set persistence.size=50Gi \
  --set resources.limits.memory=2Gi

# Upgrade
helm upgrade streamline ./helm/streamline
```

### Kubernetes (raw manifests)

```bash
kubectl apply -k k8s/
```

## Helm Chart Values

Key configuration values for the Streamline Helm chart (`helm/streamline/values.yaml`):

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `streamline` |
| `image.tag` | Container image tag | `latest` |
| `config.logLevel` | Server log level | `info` |
| `config.dataDir` | Data directory path | `/data` |
| `config.kafkaAddr` | Kafka protocol listen address | `0.0.0.0:9092` |
| `config.httpAddr` | HTTP API listen address | `0.0.0.0:9094` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.kafkaPort` | Kafka protocol port | `9092` |
| `service.httpPort` | HTTP API port | `9094` |
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

## Docker Compose Variants

| File | Description |
|------|-------------|
| `docker-compose.yml` | Standard single-node deployment |
| `docker-compose.demo.yml` | All-in-one demo with pre-seeded topics and sample data |
| `docker-compose.kafka-clients.yml` | Includes Kafka client tools for testing |

## License

Apache-2.0

