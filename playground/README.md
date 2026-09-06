# Streamline Playground

Interactive playground for trying Streamline instantly.

## Local Setup

No playground image is published. Build one from the pinned Streamline core
commit first, then name it:

```bash
scripts/prepare-core-context.sh
docker build -f playground/Dockerfile .build/core \
  --build-arg STREAMLINE_CORE_REF="$(scripts/prepare-core-context.sh --print-ref)" \
  -t streamline-playground:dev

STREAMLINE_PLAYGROUND_IMAGE=streamline-playground:dev \
  docker compose -f docker-compose.playground.yml up -d
```

The image runs as UID 1000 with `/data` created and owned at build time and
`STREAMLINE_DATA_DIR=/data`, so the playground can write even though it defaults
to in-memory storage.

## Tutorials

1. [Produce & Consume](tutorials/01-produce-consume.md) — Basic messaging in 2 minutes
2. [Consumer Groups](tutorials/02-consumer-groups.md) — Parallel processing and load balancing
3. [CDC from PostgreSQL](tutorials/03-cdc-postgres.md) — **unverified**: CDC is a
   compile-time cargo feature, the routes it describes have never been exercised
   from this repository, and the CDC demo stack is disabled
4. [StreamQL](tutorials/04-streamql.md) — **unverified** for the same reason
   (`analytics` feature, `/sql` endpoint)
5. [Schema Registry](tutorials/05-schema-registry.md) — **unverified**
   (`schema-registry` feature)

Tutorials 3–5 describe capabilities that are compiled in or absent. The
playground image is built with `full,web-ui`; unless your build includes those
features, the endpoints they use do not exist. Treat them as reading material
until a build proves otherwise.

## Kubernetes Deployment

See [k8s/](k8s/) for the playground controller manifests. They are an
**unsupported example**: no playground-controller image is built or published by
this repository, so both image references there are unpullable placeholders.

## Sharing

See [sharing/](sharing/) for shareable scenario support.

