# Streamline Playground

Interactive playground for trying Streamline instantly.

## Local Setup

```bash
docker compose -f docker-compose.playground.yml up -d
```

## Tutorials

1. [Produce & Consume](tutorials/01-produce-consume.md) — Basic messaging in 2 minutes
2. [Consumer Groups](tutorials/02-consumer-groups.md) — Parallel processing and load balancing
3. [CDC from PostgreSQL](tutorials/03-cdc-postgres.md) — Real-time database change capture
4. [StreamQL](tutorials/04-streamql.md) — SQL queries on streaming data
5. [Schema Registry](tutorials/05-schema-registry.md) — Schema management and compatibility

## Kubernetes Deployment

See [k8s/](k8s/) for the playground controller deployment manifests.

## Sharing

See [sharing/](sharing/) for shareable scenario support.
