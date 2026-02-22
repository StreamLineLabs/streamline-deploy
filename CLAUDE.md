# CLAUDE.md — Streamline Deploy

## Overview
Deployment configurations for [Streamline](https://github.com/streamlinelabs/streamline): Docker images, Helm charts, Kubernetes manifests, and monitoring stack.

## Quick Start
```bash
docker compose up -d                         # Start via Docker
helm install streamline ./helm/streamline    # Helm install
kubectl apply -k k8s/                        # Raw K8s manifests
```

## Architecture
```
├── Dockerfile                    # Multi-stage Rust build, non-root, minimal runtime
├── docker-compose.yml            # Production single-node setup
├── docker-compose.test.yml       # Integration test setup
├── docker-compose.demo.yml       # Demo with pre-seeded topics
├── docker-compose.kafka-clients.yml  # Kafka client compatibility testing
├── docker/
│   ├── Dockerfile.seed           # Data seeding image
│   ├── prometheus.yml            # Prometheus scrape config
│   └── docker-compose.benchmarks.yml
├── helm/streamline/
│   ├── Chart.yaml                # v0.2.0
│   ├── values.yaml               # Default values (security-hardened)
│   ├── values.schema.json        # JSON Schema validation
│   └── templates/
│       ├── statefulset.yaml      # StatefulSet with PVCs
│       ├── service.yaml          # Headless + LoadBalancer
│       ├── configmap.yaml        # Server configuration
│       ├── networkpolicy.yaml    # Pod-to-pod traffic rules
│       ├── servicemonitor.yaml   # Prometheus ServiceMonitor
│       ├── hpa.yaml              # Horizontal Pod Autoscaler
│       └── pdb.yaml              # PodDisruptionBudget
├── k8s/                          # Raw Kubernetes manifests + Kustomize
└── monitoring/
    ├── docker-compose.monitoring.yml  # Prometheus + Grafana sidecar
    ├── prometheus/alerts.yml     # 9 alerting rules
    └── grafana/streamline-overview.json  # 18-panel dashboard
```

## Security Defaults (Helm)
- `readOnlyRootFilesystem: true` with `/tmp` emptyDir
- `runAsNonRoot: true`, user 1000
- `allowPrivilegeEscalation: false`, drop ALL capabilities
- `networkPolicy.enabled: true` (same-namespace only on 9092/9094)

## Ports
- **9092** — Kafka wire protocol
- **9094** — HTTP API (health, metrics, management)

## Monitoring
```bash
# Start with monitoring sidecar
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
# Grafana: http://localhost:3000 (admin/streamline)
# Prometheus: http://localhost:9090
```
