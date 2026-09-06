#!/usr/bin/env bash
# Static gate: TLS documentation may not over-promise what the server encrypts.
#
# The chart mounts a certificate Secret and hands the file locations to the
# server through STREAMLINE_TLS_*. Those variables configure the **Kafka
# protocol listener (9092)**. They do not put HTTPS on the HTTP API (9094) —
# health, metrics and the management API keep serving plaintext HTTP, which is
# precisely how the chart's own probes reach them — and nothing in this chart
# asks an HTTP client for a certificate, so `tls.clientAuth` is Kafka mTLS only.
#
# The docs used to say "TLS on both Kafka and HTTP ports" and describe the
# Secret as securing the API. An operator who believed that would expose a
# management endpoint in the clear while their values file said TLS was on. The
# fix is documentation, not new wiring: the templates stay Kafka-only, and they
# say so.
#
# Hermetic: pure text inspection. No cluster, helm binary or network.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

# ---------------------------------------------------------------------------
# 1. No artifact may claim TLS covers HTTP, or that HTTP mTLS exists
# ---------------------------------------------------------------------------
# Deliberately narrow phrases: each one is a claim that was actually made, or
# the obvious way to make it again.
FORBIDDEN_CLAIMS=(
  'TLS on both'
  'both Kafka and HTTP'
  'Kafka protocol and HTTP API traffic'
  'HTTP mTLS'
  'mTLS on the HTTP'
  'secures the HTTP API'
  'HTTPS on the HTTP API is provided by the chart'
  'encrypts the HTTP API'
)

SCAN_FILES=()
while IFS= read -r f; do
  SCAN_FILES+=("$f")
done < <(find . \
  -path ./.git -prune -o \
  -path ./.build -prune -o \
  -path ./tests -prune -o \
  -name 'CHANGELOG.md' -prune -o \
  -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.tpl' -o -name '*.json' -o -name 'NOTES.txt' \) -print | sort)

# A phrase only counts as a claim when it is asserted. "There is no HTTP mTLS
# here" is the correction, not the defect, so lines that negate the phrase are
# exactly what this gate wants to see.
NEGATION_RE='\bno\b|\bnot\b|never|cannot|is not|does not|without|instead of'

for f in "${SCAN_FILES[@]}"; do
  for claim in "${FORBIDDEN_CLAIMS[@]}"; do
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s' "$line" | grep -Eqi -e "$NEGATION_RE" && continue
      fail "$f claims \"$claim\" ($line); the server's TLS settings cover the Kafka listener (9092) only — HTTPS for the HTTP API (9094) has to be terminated by an ingress, reverse proxy or mesh"
    done < <(grep -Fn "$claim" "$f" || true)
  done
done

# ---------------------------------------------------------------------------
# 2. The chart says what the TLS settings really cover
# ---------------------------------------------------------------------------
VALUES=helm/streamline/values.yaml
SCHEMA=helm/streamline/values.schema.json
NOTES=helm/streamline/templates/NOTES.txt
CONFIGMAP=helm/streamline/templates/configmap.yaml
TLS_VALUES=helm/streamline/values-tls.yaml

for f in "$VALUES" "$SCHEMA" "$NOTES" "$CONFIGMAP" "$TLS_VALUES"; do
  [ -f "$f" ] || { fail "$f is missing"; continue; }
  grep -Eq 'Kafka (protocol )?listener|Kafka listener|KAFKA PROTOCOL LISTENER|Kafka TLS|KAFKA' "$f" \
    || fail "$f must name the Kafka listener as the scope of the TLS settings"
done

grep -Eq '9094|HTTP API' "$VALUES" \
  || fail "$VALUES must state what happens to the HTTP API when TLS is enabled"
grep -Eq 'ingress|reverse proxy|service mesh' "$VALUES" \
  || fail "$VALUES must point at ingress/reverse-proxy termination for HTTP traffic"
grep -Eq 'ingress|reverse proxy|service mesh' "$NOTES" \
  || fail "$NOTES must tell the operator where HTTPS for the HTTP API comes from"
grep -Eq 'ingress|reverse proxy|service mesh' "$TLS_VALUES" \
  || fail "$TLS_VALUES must point at ingress/reverse-proxy termination for HTTP traffic"

python3 - "$SCHEMA" <<'PY' || status=1
import json, sys
schema = json.load(open(sys.argv[1]))
tls = schema["properties"]["tls"]
ok = True
if "Kafka" not in tls.get("description", ""):
    print("FAIL: values.schema.json tls description must name the Kafka listener", file=sys.stderr)
    ok = False
if "HTTP" not in tls.get("description", ""):
    print("FAIL: values.schema.json tls description must state that the HTTP API is not covered", file=sys.stderr)
    ok = False
enabled = tls["properties"]["enabled"].get("description", "")
if "Kafka" not in enabled:
    print("FAIL: values.schema.json tls.enabled must say it enables TLS on the Kafka listener", file=sys.stderr)
    ok = False
client_auth = tls["properties"]["clientAuth"].get("description", "")
if "Kafka" not in client_auth:
    print("FAIL: values.schema.json tls.clientAuth must say it applies to Kafka clients only", file=sys.stderr)
    ok = False
sys.exit(0 if ok else 1)
PY

# ---------------------------------------------------------------------------
# 3. The wiring stays Kafka-only and coherent with the probes
# ---------------------------------------------------------------------------
# The probes talk plain HTTP to 9094. If that ever changes to HTTPS the docs
# above become wrong, so pin the current, honest state.
for probe in livenessProbe readinessProbe startupProbe; do
  grep -Fq "$probe" "$VALUES" \
    || fail "$VALUES must define $probe"
done
if grep -Eq 'scheme:[[:space:]]*HTTPS' "$VALUES"; then
  fail "$VALUES probes use HTTPS, which contradicts the documented plaintext HTTP API — update both together"
fi

# The Secret is mounted for the server; the ingress is where HTTP TLS lives.
grep -Fq 'ingress' "$VALUES" \
  || fail "$VALUES must keep an ingress section: it is the supported way to serve the HTTP API over TLS"

for doc in README.md helm/README.md k8s/README.md; do
  [ -f "$doc" ] || continue
  grep -Eq 'Kafka listener|Kafka protocol listener|Kafka TLS|Kafka \(9092\)|Kafka listener \(9092\)' "$doc" \
    || fail "$doc must scope its TLS description to the Kafka listener"
done

if [ "$status" -eq 0 ]; then
  echo "tls-scope gate passed: TLS is documented as Kafka-listener only, HTTP TLS is an ingress concern"
fi

exit "$status"
