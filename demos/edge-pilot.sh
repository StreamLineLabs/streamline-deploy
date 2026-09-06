#!/usr/bin/env bash
# Edge Fleet Pilot Demo — DISABLED (unsupported).
#
# This script used to start an "edge appliance", publish MQTT sensor data to
# :1883 and claim the readings reached a cloud broker. None of that is
# demonstrable from this repository:
#
#   * No verified Streamline build opens an MQTT listener. The bridge, the
#     store-and-forward buffer and the cloud-sync loop are unverified claims
#     about core; no smoke test, conformance run or published image exercises
#     them.
#   * No edge image exists anywhere. The single publisher
#     (.github/workflows/docker-publish.yml) builds `Dockerfile` and pushes
#     ghcr.io/streamlinelabs/streamline only, so `streamline-edge` has never
#     been built or pushed by anything here.
#   * The compose stack this script drove (docker-compose.edge.yml) has been
#     removed rather than left as a runnable surface for behaviour nobody can
#     confirm.
#
# It therefore fails closed: it starts nothing, pulls nothing and touches no
# Docker resources. Dockerfile.edge is kept as an unsupported *source
# reference* only. tests/edge-unsupported_test.sh keeps it that way.
set -euo pipefail

cat >&2 <<'MSG'
error: the edge pilot demo is disabled.

Streamline's edge runtime (MQTT bridge on 1883, store-and-forward, cloud sync)
is not verified against core, and no edge image is built or published by this
repository. There is nothing to run, so this demo refuses to start containers
instead of pretending a pipeline works.

What exists today:
  * Dockerfile.edge                    unsupported source reference, unbuilt
  * docker/edge/streamline-edge.toml   reference config, edge/MQTT disabled

Restoring this demo means, in order: verifying the listeners against a real
core build, re-enabling the configuration, adding a smoke test that asserts
data actually flows, and only then bringing back a runnable compose stack.
MSG
exit 1
