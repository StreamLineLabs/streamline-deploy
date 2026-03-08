# Port Reference

| Port | Protocol | Purpose |
|------|----------|---------|
| 9092 | TCP | Kafka wire protocol (client connections) |
| 9094 | HTTP | REST API, health checks, metrics |
| 8080 | HTTP | Prometheus metrics (when enabled) |
| 7946 | TCP/UDP | Cluster gossip (multi-node mode) |
