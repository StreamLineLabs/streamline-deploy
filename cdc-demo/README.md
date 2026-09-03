# CDC demo fixtures — reference only, pipeline DISABLED

These files belong to `docker-compose.cdc-demo.yml`, which is **disabled**:
every service sits behind the `disabled` Compose profile and
`demos/cdc-demo.sh` exits non-zero instead of starting anything.

| File | What it is | Status |
|------|------------|--------|
| `init.sql` | Creates the demo tables and a logical-replication publication | Plain PostgreSQL; runs if you start Postgres yourself |
| `seed.sql` | Inserts sample rows | Plain PostgreSQL |
| `cdc-source.json` | Example CDC source-registration body | **Unverified** — the field names, nesting and the route it would be posted to have never been accepted by a running Streamline server in this repository |

`cdc-source.json` is kept as a shape sketch, not as a working request. Do not
treat it (or any CDC route mentioned in older docs) as an API contract: CDC is a
compile-time cargo feature, no published image is built with it, and nothing
here has ever exercised the endpoint. Capture the real payload from a server
built with the `cdc` feature before relying on it.

See the header of `docker-compose.cdc-demo.yml` for the full reasoning and the
checklist for re-enabling the demo.
