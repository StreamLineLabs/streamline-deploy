# Contributing to Streamline Deploy

Thank you for your interest in contributing! Please review the [organization-wide contributing guidelines](https://github.com/streamlinelabs/.github/blob/main/CONTRIBUTING.md) first.

## Development Setup

### Prerequisites

- Docker & Docker Compose
- Helm 3.x (for Helm chart development)
- kubectl (for Kubernetes manifest testing)

### Local Development

```bash
# Start Streamline with Docker Compose
docker compose up -d

# Start with demo data
docker compose -f docker-compose.demo.yml up -d

# Start benchmark comparison (Streamline vs Kafka vs Redpanda)
docker compose -f docker-compose.benchmark.yml up -d
```

### Helm Chart Development

```bash
# Lint the chart
helm lint helm/streamline/

# Template rendering (dry run)
helm template streamline helm/streamline/ --values helm/streamline/values.yaml

# Validate schema
helm install streamline helm/streamline/ --dry-run --debug

# Install to a cluster
helm install streamline helm/streamline/
```

### Kubernetes Manifests

```bash
# Apply with kustomize
kubectl apply -k k8s/

# Validate manifests
kubectl apply -k k8s/ --dry-run=client
```

## Architecture

- `helm/streamline/` — Helm chart (StatefulSet, Services, PDB, ConfigMap)
- `k8s/` — Raw Kubernetes manifests with Kustomize
- `docker/` — Dockerfiles
- `docker-compose*.yml` — Docker Compose configurations

## License

By contributing, you agree that your contributions will be licensed under the Apache-2.0 License.
