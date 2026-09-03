# Port Reference

The Kafka and HTTP listeners are **fixed**: the container ports, probes,
Services, NetworkPolicies and metrics wiring in this repository all use these
numbers literally, and the Helm chart rejects values that pretend to move them
(`values.schema.json` plus a render-time guard). Publish a different port
outside the pod with your own Service, an ingress, or `kubectl port-forward`.

| Port | Protocol | Purpose | Status |
|------|----------|---------|--------|
| 9092 | TCP | Kafka wire protocol (client connections) | Fixed |
| 9094 | HTTP | REST API, health checks, **and Prometheus metrics at `/metrics`** | Fixed; plaintext HTTP |
| 9093 | TCP | Reserved for inter-broker traffic | Declared, but nothing listens: clustering is unsupported |
| 1883 | TCP | MQTT bridge (edge) | **Unsupported/unverified** — nothing here binds it |

Notes:

* There is no separate metrics port. Metrics are served by the HTTP API on 9094;
  a "metrics on 8080" entry used to appear here and matched no artifact.
* There is no cluster gossip port. Peer bootstrap is not implemented, the chart
  and raw manifests deploy one standalone broker, and 9093 is reserved shape
  only.
* TLS configured through the chart protects the **Kafka listener (9092)**. The
  HTTP API is not covered; terminate HTTPS in front of it.
