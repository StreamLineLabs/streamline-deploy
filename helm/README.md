# Streamline Helm Chart

Helm chart for deploying Streamline on Kubernetes.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.0+

## Installation

```bash
# Add the chart repository (if hosted)
# helm repo add streamline https://streamlinelabs.github.io/charts

# Install with default values
helm install streamline ./streamline

# Install with custom values
helm install streamline ./streamline -f my-values.yaml

# Install in a specific namespace
helm install streamline ./streamline -n streaming --create-namespace
```

## Configuration

See [values.yaml](streamline/values.yaml) for all configurable options.

### Common configurations

#### Production deployment (3 replicas)

```yaml
replicaCount: 3

persistence:
  size: 100Gi
  storageClass: "fast-ssd"

resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

#### Enable external access

```yaml
externalService:
  enabled: true
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

#### Enable Prometheus monitoring

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
```

## Upgrading

```bash
helm upgrade streamline ./streamline -f my-values.yaml
```

## Uninstalling

```bash
helm uninstall streamline

# PVCs are not deleted automatically - to clean up:
kubectl delete pvc -l app.kubernetes.io/name=streamline
```
