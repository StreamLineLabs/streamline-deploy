# Streamline Kubernetes Deployment

This directory contains Kubernetes manifests for deploying Streamline.

## Quick Start

### Prerequisites
- Kubernetes cluster (1.21+)
- kubectl configured to access your cluster
- Docker image built and pushed to a registry

### Build and Push Docker Image

```bash
# Build the image
docker build -t your-registry/streamline:latest .

# Push to registry
docker push your-registry/streamline:latest
```

### Deploy with Kustomize

```bash
# Update image reference
cd k8s
kustomize edit set image streamline=your-registry/streamline:latest

# Deploy all resources
kubectl apply -k .

# Or deploy without kustomize
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
kubectl apply -f statefulset.yaml
kubectl apply -f pod-disruption-budget.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n streamline

# Check services
kubectl get svc -n streamline

# View logs
kubectl logs -n streamline streamline-0

# Port forward for local access
kubectl port-forward -n streamline svc/streamline 9092:9092
```

## Components

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates isolated namespace for Streamline |
| `configmap.yaml` | Server configuration (env vars) |
| `service.yaml` | Client, headless, and external services |
| `statefulset.yaml` | Main deployment with persistent storage |
| `pod-disruption-budget.yaml` | HA during maintenance |
| `servicemonitor.yaml` | Prometheus Operator integration |
| `kustomization.yaml` | Kustomize base configuration |

## Configuration

### Environment Variables

Modify `configmap.yaml` to change settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `STREAMLINE_LOG_LEVEL` | `info` | Log level (trace, debug, info, warn, error) |
| `STREAMLINE_DATA_DIR` | `/data` | Data directory path |
| `STREAMLINE_LISTEN_ADDR` | `0.0.0.0:9092` | Kafka protocol listen address |
| `STREAMLINE_HTTP_ADDR` | `0.0.0.0:9094` | HTTP API listen address |

### Scaling

```bash
# Scale to 3 replicas for HA cluster
kubectl scale statefulset streamline -n streamline --replicas=3
```

### Storage

The StatefulSet uses a PersistentVolumeClaim template. Configure:

```yaml
# In statefulset.yaml
volumeClaimTemplates:
  - spec:
      storageClassName: "your-storage-class"  # e.g., "gp2", "standard"
      resources:
        requests:
          storage: 100Gi  # Adjust based on needs
```

### Resource Limits

Adjust resources in `statefulset.yaml`:

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

## Monitoring

### Prometheus Integration

If using Prometheus Operator:

```bash
kubectl apply -f servicemonitor.yaml
```

Metrics are exposed at `http://streamline:9094/metrics`

### Health Checks

- Liveness: `GET /health/live`
- Readiness: `GET /health/ready`

## Production Recommendations

1. **High Availability**: Run at least 3 replicas
2. **Storage**: Use fast SSD-backed storage classes
3. **Network Policies**: Restrict ingress to Kafka port
4. **TLS**: Enable TLS for client and inter-broker communication
5. **Resource Quotas**: Set appropriate limits for namespace
6. **Backup**: Implement regular PV snapshots

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n streamline streamline-0
kubectl logs -n streamline streamline-0 --previous
```

### Connection issues

```bash
# Test internal connectivity
kubectl run -n streamline test --rm -it --image=busybox -- nc -vz streamline 9092
```

### Storage issues

```bash
# Check PVC status
kubectl get pvc -n streamline
kubectl describe pvc -n streamline data-streamline-0
```
