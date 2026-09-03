#!/usr/bin/env bash
# Static gate: no runnable edge surface, and no edge runtime claims.
#
# The edge appliance shipped a full set of runnable artefacts for behaviour that
# nothing in this repository can demonstrate: a compose stack that mapped
# :1883 and started an "MQTT bridge", a pilot demo that published sensor data to
# it and printed a success banner, an image that EXPOSEd 1883, and a config that
# switched the bridge on. Core's edge features are unverified here — no smoke
# test, conformance run or published image exercises an MQTT listener,
# store-and-forward buffer or cloud sync — and no edge image has ever been built
# or pushed by anything in this repository.
#
# So the runnable surfaces are gone: docker-compose.edge.yml is removed and
# demos/edge-pilot.sh fails closed without touching Docker. Dockerfile.edge is
# kept as an explicitly unsupported *source reference*, and this gate stops the
# claims from creeping back in with it.
#
# Hermetic: text inspection plus running the (container-free) demo script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

config_lines() {
  grep -vE '^[[:space:]]*#' "$1"
}

# ---------------------------------------------------------------------------
# 1. No runnable edge stack
# ---------------------------------------------------------------------------
[ -e docker-compose.edge.yml ] \
  && fail "docker-compose.edge.yml is back; the edge stack must not be runnable while its runtime is unverified"

shopt -s nullglob
compose_files=(docker-compose*.yml */docker-compose*.yml)
shopt -u nullglob
[ "${#compose_files[@]}" -gt 0 ] || fail "no docker-compose*.yml found"

for compose in "${compose_files[@]}"; do
  if config_lines "$compose" | grep -Eq '(^|[^0-9])1883([^0-9]|$)'; then
    fail "$compose binds or references port 1883; no verified Streamline build opens an MQTT listener"
  fi
  if config_lines "$compose" | grep -Eqi 'mosquitto|mqtt'; then
    fail "$compose wires an MQTT client/broker for a bridge that is not verified against core"
  fi
  if config_lines "$compose" | grep -Eqi 'STREAMLINE_EDGE_|EDGE_ID|CLOUD_ENDPOINT'; then
    fail "$compose configures the unverified edge runtime"
  fi
done

# Raw manifests must not expose it either.
while IFS= read -r manifest; do
  if config_lines "$manifest" | grep -Eq 'containerPort:[[:space:]]*1883|port:[[:space:]]*1883'; then
    fail "$manifest exposes port 1883"
  fi
done < <(find k8s helm playground -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# 2. The demo entry point fails closed and starts nothing
# ---------------------------------------------------------------------------
PILOT=demos/edge-pilot.sh
if [ -f "$PILOT" ]; then
  if config_lines "$PILOT" | grep -Eq 'docker (compose|run|start)'; then
    fail "$PILOT still drives Docker; it must refuse to start anything while the edge runtime is unverified"
  fi
  if bash "$PILOT" >/dev/null 2>&1; then
    fail "$PILOT exited 0; a disabled demo must fail closed"
  fi
  message="$(bash "$PILOT" 2>&1 >/dev/null || true)"
  case "$message" in
    *disabled*) ;;
    *) fail "$PILOT must say the demo is disabled, got: $message" ;;
  esac
  case "$message" in
    *1883*|*MQTT*) ;;
    *) fail "$PILOT must explain which claim is unverified (the MQTT bridge on 1883)" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 3. Dockerfile.edge is a marked, unbuilt reference
# ---------------------------------------------------------------------------
EDGE_DOCKERFILE=Dockerfile.edge
if [ -f "$EDGE_DOCKERFILE" ]; then
  grep -Fq 'UNSUPPORTED REFERENCE' "$EDGE_DOCKERFILE" \
    || fail "$EDGE_DOCKERFILE must be marked UNSUPPORTED REFERENCE"
  if grep -Eq '^EXPOSE .*1883' "$EDGE_DOCKERFILE"; then
    fail "$EDGE_DOCKERFILE must not EXPOSE 1883: EXPOSE advertises a listener no verified build opens"
  fi
  grep -Fq 'dev.streamline.support="unsupported-reference"' "$EDGE_DOCKERFILE" \
    || fail "$EDGE_DOCKERFILE must label the image as an unsupported reference"

  # Nothing may build or push it.
  for wf in .github/workflows/*.yml; do
    if grep -Fq 'Dockerfile.edge' "$wf"; then
      fail "$wf references $EDGE_DOCKERFILE; no workflow may build or publish an edge image"
    fi
  done
  if grep -Eq '^[a-zA-Z_-]+:.*' Makefile && grep -Fq 'Dockerfile.edge' Makefile; then
    fail "Makefile references $EDGE_DOCKERFILE; there is no supported edge build"
  fi
fi

# ---------------------------------------------------------------------------
# 4. The bundled edge configuration ships disabled
# ---------------------------------------------------------------------------
EDGE_CONFIG=docker/edge/streamline-edge.toml
if [ -f "$EDGE_CONFIG" ]; then
  grep -Fq 'UNSUPPORTED REFERENCE' "$EDGE_CONFIG" \
    || fail "$EDGE_CONFIG must be marked UNSUPPORTED REFERENCE"
  awk -v section='\\[edge\\]' '
    $0 ~ "^" section { inside = 1; next }
    inside && /^\[/ { inside = 0 }
    inside && /^enabled[[:space:]]*=[[:space:]]*true/ { found = 1 }
    END { exit found ? 1 : 0 }
  ' "$EDGE_CONFIG" || fail "$EDGE_CONFIG must ship [edge] enabled = false"
  awk -v section='\\[mqtt\\]' '
    $0 ~ "^" section { inside = 1; next }
    inside && /^\[/ { inside = 0 }
    inside && /^enabled[[:space:]]*=[[:space:]]*true/ { found = 1 }
    END { exit found ? 1 : 0 }
  ' "$EDGE_CONFIG" || fail "$EDGE_CONFIG must ship [mqtt] enabled = false"
fi

# ---------------------------------------------------------------------------
# 5. Documentation makes no runnable edge promise
# ---------------------------------------------------------------------------
# Naming the removed artefacts while saying they are gone is documentation;
# naming them as something to run is the regression.
REMOVAL_RE='removed|no longer|does not exist|never|was deleted|is gone|disabled'

while IFS= read -r doc; do
  case "$doc" in
    ./CHANGELOG.md|./tests/*) continue ;;
  esac
  for artefact in docker-compose.edge.yml STREAMLINE_EDGE_IMAGE; do
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      printf '%s' "$match" | grep -Eqi -e "$REMOVAL_RE" && continue
      fail "$doc:$match presents $artefact as usable; the edge stack was removed because its runtime is unverified"
    done < <(grep -Fn "$artefact" "$doc" || true)
  done
done < <(find . -path ./.git -prune -o -path ./.build -prune -o -type f -name '*.md' -print | sort)

if [ "$status" -eq 0 ]; then
  echo "edge gate passed: no runnable edge surface, no 1883 binding, reference image marked unsupported"
fi

exit "$status"
