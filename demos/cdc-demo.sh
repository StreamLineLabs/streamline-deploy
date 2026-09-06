#!/usr/bin/env bash
# CDC → Streamline demo — DISABLED (unverified).
#
# The documented entry point for docker-compose.cdc-demo.yml. It starts
# nothing: the pipeline that stack advertised cannot be shown to work from this
# repository, so the demo fails closed instead of walking a reader through
# requests that may not exist.
#
# See the header of docker-compose.cdc-demo.yml for the full reasoning and the
# checklist for re-enabling it.
set -euo pipefail

cat >&2 <<'MSG'
error: the CDC demo is disabled.

Its pipeline is unverified end to end: the CDC source-registration route, the
JSON body in cdc-demo/cdc-source.json, the start route, the message-read path
and the StreamQL endpoint were taken from documentation, not from a server
anyone ran here. Nothing in this repository can tell you whether they answer or
404, so the demo refuses to start containers and print a success banner.

Also true regardless of the routes:
  * cdc and analytics are compile-time cargo features; no environment variable
    turns them on, and no published tag is built with them.
  * this repository ships no core sources, so nothing here can build such an
    image for you.

Every service in docker-compose.cdc-demo.yml sits behind the `disabled` Compose
profile, and its Streamline image default is a local-only placeholder that
matches nothing in any registry.

Re-enabling means, in order: build an image with the cdc and analytics features
from the pinned core commit, capture the routes and payloads that server really
accepts, add a test that asserts rows reach a topic, then drop the profile.
MSG
exit 1
