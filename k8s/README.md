# Streamline Kubernetes Deployment

This directory contains Kubernetes manifests for deploying Streamline.

## Quick Start

### Prerequisites
- Kubernetes cluster (1.21+)
- kubectl configured to access your cluster
- A Streamline image your cluster can pull (see below — none is published yet)

### Build the image

This repository ships **no Streamline core sources**: `Dockerfile` compiles the
core crates, so its build context must be a checkout of the core repository at
the commit pinned in [`core-source.env`](../core-source.env). Building with this
repository as the context (`docker build -t … .`) cannot work — it only ever
produced a "Cargo.toml not found" failure.

Prepare the context, then build against it:

```bash
# Materialise the pinned core sources into .build/core (+ the .deploy/ overlay)
scripts/prepare-core-context.sh          # or: make core-context

# Build from that context — never from this repository
docker build -f Dockerfile .build/core \
  --build-arg STREAMLINE_EDITION=full \
  --build-arg STREAMLINE_FEATURES=full \
  --build-arg STREAMLINE_CORE_REF="$(scripts/prepare-core-context.sh --print-ref)" \
  -t your-registry/streamline:<tag>

docker push your-registry/streamline:<tag>
```

`make docker` does the same thing in one step (it tags `streamline:dev`).

Both commands fail until a maintainer pins a full 40-character core commit SHA
in `core-source.env`; that is deliberate, and the CI image gate is red for the
same reason.

### Deploy with Kustomize

No Streamline image is published yet, so the base carries a deliberately
unpullable placeholder (`streamline:set-image-before-apply`). Point it at the
image you built and pushed:

```bash
cd k8s
kustomize edit set image streamline=your-registry/streamline:<tag>

# Deploy all resources
kubectl apply -k .

# Or deploy without kustomize (edit the image in statefulset.yaml first)
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
kubectl apply -f statefulset.yaml
kubectl apply -f pod-disruption-budget.yaml
```

Applying the base unchanged leaves the pod in `ImagePullBackOff` — visibly
broken instead of quietly wrong.

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
| `statefulset.yaml` | Single standalone broker with persistent storage |
| `pod-disruption-budget.yaml` | Limits voluntary evictions (not HA: one broker) |
| `servicemonitor.yaml` | Prometheus Operator integration |
| `kustomization.yaml` | Kustomize base configuration |
| `keda/` | KEDA autoscaling example — **unsupported**, not applied by `kustomization.yaml` |

## Configuration

### Environment Variables

Modify `configmap.yaml` to change settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `STREAMLINE_LOG_LEVEL` | `info` | Log level (trace, debug, info, warn, error) |
| `STREAMLINE_DATA_DIR` | `/data` | Data directory path |
| `STREAMLINE_LISTEN_ADDR` | `0.0.0.0:9092` | Kafka protocol listen address |
| `STREAMLINE_HTTP_ADDR` | `0.0.0.0:9094` | HTTP API listen address |
| `STREAMLINE_AUTO_CREATE_TOPICS` | `"false"` | Auto-create topics on first produce. Set explicitly: core enables it by default, so removing the key turns auto-creation back **on** |

### Scaling

**Horizontal scaling is not supported.** These manifests deploy a *single
standalone broker*: Streamline has no peer bootstrap (stable node IDs, seed
nodes) yet, so additional pods would come up as independent brokers with their
own data directory and topic metadata. They would not replicate, form a quorum
or survive the loss of a pod — clients would simply see different topic sets
depending on which pod they reached.

Do **not** run:

```bash
# UNSUPPORTED — creates independent brokers, not an HA cluster
kubectl scale statefulset streamline -n streamline --replicas=3
```

Scale vertically instead (see *Resource Limits* below) and grow the PVC. The
Helm chart enforces the same rule at render time (`replicaCount > 1`,
`config.clusterEnabled`, `autoscaling.enabled` and `keda.enabled` all fail).

### Autoscaling (`k8s/keda/`, unsupported)

The `k8s/keda/` directory contains a KEDA `ScaledObject` and
`TriggerAuthentication` **example only**. It is not part of
`kustomization.yaml` and must not be applied against this StatefulSet: a
ScaledObject changes the replica count, which is exactly the unsupported
scaling described above (and it scales to zero when idle). The example is kept
to document the intended shape once clustered mode exists; the metric names it
queries are also unverified against core
([`monitoring/METRICS.md`](../monitoring/METRICS.md)).

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

1. **Single broker only**: keep `replicas: 1` — there is no clustering, so
   extra pods are independent brokers, not an HA quorum. Plan for the downtime
   of a pod restart (a PodDisruptionBudget only limits *voluntary* evictions).
2. **Storage**: Use fast SSD-backed storage classes; capacity is the main
   scaling dimension
3. **Network Policies**: Restrict ingress to Kafka port
4. **TLS**: the server's TLS settings cover the **Kafka listener (9092) only**.
   The HTTP API on 9094 (health, metrics, management) serves plaintext HTTP —
   these manifests' probes use it that way — so put an ingress controller,
   reverse proxy or service mesh in front of it if that traffic must be
   encrypted. There is no HTTP mTLS here.
5. **Resource Quotas**: Set appropriate limits for namespace
6. **Backup**: Implement regular PV snapshots — with one broker there is no
   replica to fall back on

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
