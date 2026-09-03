# Streamline Helm Chart

Helm chart for deploying Streamline on Kubernetes.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.0+

## Installation

There is **no chart repository and no published image**. The chart is installed
from this directory, and it ships no default `image.tag`: nothing has been
pushed, so a default would render every workload against a manifest that does
not exist. Name an image you built (see the repository README, "Building the
Official Image") and pushed where the cluster can pull it:

```bash
# Install, naming the image explicitly
helm install streamline ./streamline \
  --set image.repository=my-registry/streamline \
  --set image.tag=<tag>

# Install with custom values
helm install streamline ./streamline -f my-values.yaml \
  --set image.repository=my-registry/streamline --set image.tag=<tag>

# Install in a specific namespace
helm install streamline ./streamline -n streaming --create-namespace \
  --set image.repository=my-registry/streamline --set image.tag=<tag>
```

Omitting them fails the render with an explanation, rather than installing a
StatefulSet that lands in `ImagePullBackOff`:

```console
$ helm template streamline ./streamline
Error: ... streamline: image.tag is empty and this chart ships no default tag,
because no Streamline image is published yet. ...
```

## Image Capabilities

SASL authentication only works with an image built with that feature. Declare
what the configured image supports with `image.edition`. Switching on a feature
the image does not advertise **fails the render**.

The full image compiles clustering support, but this chart rejects
`config.clusterEnabled=true` and `replicaCount > 1` until stable node IDs and
seed-node bootstrap are implemented.

| Edition | `image.capabilities` | Capabilities |
|---------|----------------------|--------------|
| `full` (default) | must be empty | `auth`, `clustering` — the build the publisher makes (`STREAMLINE_FEATURES=full`) |
| `standard` | must be empty | none — a build with default cargo features |
| `custom` | **required** | exactly what you declare: `auth`, `clustering`, `moonshot`, or `none` |

A `custom` image is `STREAMLINE_EDITION=custom` with an arbitrary
`STREAMLINE_FEATURES` list, so nothing about it is inferable. The chart refuses
to guess:

```bash
helm install streamline ./streamline \
  --set image.repository=my-registry/streamline --set image.tag=<tag> \
  --set image.edition=custom --set image.capabilities='{auth}'
```

Declaring capabilities on `standard`/`full` is rejected too — their capability
sets follow from the build, and a second source of truth is a second thing to
get wrong. An image that declares only `clustering` cannot switch `auth.enabled`
on: inferring "yes" would deploy an unauthenticated broker while the values file
says authentication is enabled.

TLS is **not** a capability: Streamline core compiles TLS into every build, so
`tls.enabled` works with any edition, including a custom `standard` build.
`"tls"` is still accepted inside `image.capabilities` for backwards
compatibility and is ignored.

## Listener ports are fixed

The Kafka listener is fixed at **9092** and the HTTP API at **9094**. The
container ports, the named ports the probes and Services target, the
NetworkPolicy rules, the ServiceMonitor endpoint and the Prometheus annotations
are all literal, so a "custom port" produced a Service pointing at a port
nothing served and probes aimed at the old one — a broker that never became
ready, for a reason the values file did not explain.

`service.kafkaPort`, `service.httpPort`, `externalService.kafkaPort`,
`config.kafkaAddr`, `config.httpAddr` and `config.interBrokerPort` are therefore
validated by `values.schema.json` *before* rendering, and again by the chart:

```console
$ helm template streamline ./streamline --set service.httpPort=8080 ...
Error: values don't meet the specifications of the schema(s) ...
- at '/service/httpPort': value must be 9094
```

Publish a different port outside the pod instead — your own Service, an
ingress, or `kubectl port-forward`.

The experimental moonshot feature set is advertised by no edition, and this
chart cannot configure it yet: no template renders the `moonshot.*` settings
into the ConfigMap or the container arguments. Enabling any of them **fails the
render** rather than deploying a server that ignores them, and listing
`moonshot` in `image.capabilities` does not change that — it only describes what
the image contains.

## Configuration

See [values.yaml](streamline/values.yaml) for all configurable options.

### Common configurations

#### Production deployment (single broker)

Streamline runs as **one broker** under this chart: `replicaCount > 1`,
`config.clusterEnabled`, `autoscaling.enabled` and `keda.enabled` all fail the
render until peer bootstrap is implemented. Scale vertically and on storage:

```yaml
replicaCount: 1

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

#### Autoscaling (not supported yet)

`autoscaling` (HPA) and `keda` (ScaledObject) keys exist in `values.yaml`, but
**switching either on fails the render**:

```console
$ helm template streamline ./streamline --set autoscaling.enabled=true \
    --set image.repository=my-registry/streamline --set image.tag=<tag>
Error: ... streamline: autoscaling.enabled=true is not supported by this chart
yet. The autoscaler scales the StatefulSet above one replica, ...
```

An autoscaler writes the StatefulSet's replica count itself, after install, so
allowing it would bypass the `replicaCount > 1` guard without the operator ever
seeing a value that says so. The extra pods would start as independent brokers
with their own data directory and topic metadata — not as members of a cluster,
because the chart renders no peer IDs or seed nodes. The keys stay in
`values.yaml` to document the intended shape once clustered mode exists.

The raw-manifest example in [`k8s/keda/`](../k8s/keda/) is unsupported for the
same reason and must not be applied against the standalone StatefulSet.

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

> The bundled alert rules and dashboards use metric names that have not been
> verified against Streamline core — see
> [`monitoring/METRICS.md`](../monitoring/METRICS.md).

#### Enable Kafka TLS with an existing Secret

**Scope first:** these settings encrypt the **Kafka protocol listener (9092)**.
They do not put HTTPS on the HTTP API (9094) — health, metrics and the
management API keep serving plaintext HTTP, which is how this chart's own probes
reach them — and `tls.clientAuth` is mutual TLS for *Kafka* clients: nothing
here asks an HTTP client for a certificate. To serve the HTTP API over TLS,
terminate it in front of the Service with the chart's `ingress.tls` list, a
reverse proxy or a service mesh.

```bash
kubectl create secret tls streamline-tls --cert=server.crt --key=server.key
```

```yaml
tls:
  enabled: true
  existingSecret: streamline-tls   # tls.crt / tls.key (+ ca.crt for Kafka mTLS)
  mountPath: /etc/streamline/tls
  clientAuth: false
```

The Secret is mounted read-only at `mountPath` and the server is pointed at the
files through the environment variables core actually reads. All four configure
the Kafka listener:

| Variable | Set when | Scope |
|----------|----------|-------|
| `STREAMLINE_TLS_CERT` | `tls.enabled` | Kafka listener (9092) |
| `STREAMLINE_TLS_KEY` | `tls.enabled` | Kafka listener (9092) |
| `STREAMLINE_TLS_CA_CERT` | `tls.clientAuth`, or `tls.caData` is supplied | Kafka client certificates |
| `STREAMLINE_TLS_REQUIRE_CLIENT_CERT` | `tls.clientAuth` | Kafka client certificates |

A ready-made example lives in
[streamline/values-tls.yaml](streamline/values-tls.yaml).

#### Enable SASL authentication with an existing Secret

Streamline core authenticates against a **YAML users file** that holds
precomputed password hashes / SCRAM credentials. It does not read a username or
password from the environment, so the chart cannot turn a plaintext value in
`values.yaml` into a working credential. `auth.enabled: true` therefore
**requires** `auth.existingSecret`; inline `auth.sasl.username` /
`auth.sasl.password` are rejected at render time rather than quietly ignored.

Create the users file with your own tooling, then:

```bash
kubectl create secret generic streamline-auth --from-file=users.yaml
```

```yaml
image:
  edition: full        # the image must support auth

auth:
  enabled: true
  existingSecret: streamline-auth
  usersFileKey: users.yaml           # key inside that Secret
  mountPath: /etc/streamline/auth    # mounted read-only
  sasl:
    mechanisms:
      - SCRAM-SHA-256
```

Only `usersFileKey` is projected from the Secret, mounted read-only with mode
`0440`. The server is configured through `STREAMLINE_AUTH_USERS_FILE`
(`<mountPath>/<usersFileKey>`) and `STREAMLINE_AUTH_SASL_MECHANISMS` (the
comma-separated `auth.sasl.mechanisms` list). Rotate credentials by updating the
Secret and restarting the StatefulSet.

#### Pass extra server arguments

```yaml
config:
  extraArgs:
    - --max-message-bytes
    - "10485760"
```

Extra arguments are appended after the image's default `--listen-addr` and
`--data-dir` flags. Only flags the pinned image actually accepts belong here —
an unknown flag makes the server exit at startup.

## Upgrading

```bash
helm upgrade streamline ./streamline -f my-values.yaml \
  --set image.repository=my-registry/streamline --set image.tag=<tag>
```

## Uninstalling

```bash
helm uninstall streamline

# PVCs are not deleted automatically - to clean up:
kubectl delete pvc -l app.kubernetes.io/name=streamline
```
