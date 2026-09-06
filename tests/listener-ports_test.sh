#!/usr/bin/env bash
# Static gate: the listener ports stay fixed at 9092 (Kafka) and 9094 (HTTP).
#
# `service.kafkaPort`, `service.httpPort`, `config.kafkaAddr` and
# `config.httpAddr` looked like knobs, but only some of them reached anything:
# the container `ports:` block, the named ports the probes and Services target,
# the NetworkPolicy rules, the ServiceMonitor endpoint and the Prometheus
# annotations are all literal. Changing a "port" therefore produced a Service
# pointing at a port nothing served, probes still aimed at the old container
# port, and a NetworkPolicy blocking the new one — a broker that never became
# ready, for a reason the values file did not explain.
#
# Until every one of those places is rendered from one source, the conservative
# rule is the honest one: the ports are fixed, custom values are rejected before
# rendering (values.schema.json) and again inside the templates, and the raw
# manifests use the same two numbers.
#
# Hermetic: pure text/JSON inspection. No cluster or helm binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SCHEMA=helm/streamline/values.schema.json
VALUES=helm/streamline/values.yaml
HELPERS=helm/streamline/templates/_helpers.tpl
STS=helm/streamline/templates/statefulset.yaml
SVC=helm/streamline/templates/service.yaml
NETPOL=helm/streamline/templates/networkpolicy.yaml

KAFKA_PORT=9092
INTER_BROKER_PORT=9093
HTTP_PORT=9094

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

for f in "$SCHEMA" "$VALUES" "$HELPERS" "$STS" "$SVC" "$NETPOL"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. The schema rejects custom ports before a single template runs
# ---------------------------------------------------------------------------
python3 - "$SCHEMA" "$KAFKA_PORT" "$HTTP_PORT" "$INTER_BROKER_PORT" <<'PY' || status=1
import json, sys
schema_path, kafka, http, inter = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
schema = json.load(open(schema_path))
props = schema["properties"]
ok = True

def require_enum(node, path, expected):
    global ok
    enum = node.get("enum")
    if enum != [expected]:
        print(f"FAIL: {schema_path} {path} must be pinned to {expected} (enum: {enum})", file=sys.stderr)
        ok = False

require_enum(props["service"]["properties"]["kafkaPort"], "service.kafkaPort", kafka)
require_enum(props["service"]["properties"]["httpPort"], "service.httpPort", http)
require_enum(props["externalService"]["properties"]["kafkaPort"], "externalService.kafkaPort", kafka)
require_enum(props["config"]["properties"]["interBrokerPort"], "config.interBrokerPort", inter)

for key, port in (("kafkaAddr", kafka), ("httpAddr", http)):
    pattern = props["config"]["properties"][key].get("pattern", "")
    if not pattern.endswith(f":{port}$"):
        print(f"FAIL: {schema_path} config.{key} pattern {pattern!r} must require port {port}", file=sys.stderr)
        ok = False

sys.exit(0 if ok else 1)
PY

# ---------------------------------------------------------------------------
# 2. The chart rejects them again at render time, with an actionable message
# ---------------------------------------------------------------------------
grep -Fq 'define "streamline.rejectCustomListenerPorts"' "$HELPERS" \
  || fail "$HELPERS must define streamline.rejectCustomListenerPorts"
grep -Fq 'include "streamline.rejectCustomListenerPorts"' "$HELPERS" \
  || fail "$HELPERS must call streamline.rejectCustomListenerPorts from streamline.validateConfiguration, or the guard never runs"

for setting in service.kafkaPort service.httpPort externalService.kafkaPort config.kafkaAddr config.httpAddr config.interBrokerPort networkPolicy.ingress; do
  grep -Fq "$setting" "$HELPERS" \
    || fail "$HELPERS must reject a custom $setting"
done

# The message has to tell the operator what to do instead.
grep -Eq 'Service, ingress or port-forward|expose a different port outside the pod' "$HELPERS" \
  || fail "$HELPERS must point at the supported way to publish another port"

# Every workload template runs the validation.
for tpl in "$STS" helm/streamline/templates/configmap.yaml helm/streamline/templates/hpa.yaml helm/streamline/templates/keda-scaledobject.yaml; do
  [ -f "$tpl" ] || continue
  grep -Fq 'include "streamline.validateConfiguration"' "$tpl" \
    || fail "$tpl must include streamline.validateConfiguration"
done

# ---------------------------------------------------------------------------
# 3. The shipped values are the fixed ports
# ---------------------------------------------------------------------------
grep -Eq '^[[:space:]]+kafkaPort:[[:space:]]*'"$KAFKA_PORT"'([[:space:]]|#|$)' "$VALUES" \
  || fail "$VALUES must ship service.kafkaPort: $KAFKA_PORT"
grep -Eq '^[[:space:]]+httpPort:[[:space:]]*'"$HTTP_PORT"'([[:space:]]|#|$)' "$VALUES" \
  || fail "$VALUES must ship service.httpPort: $HTTP_PORT"
grep -Eq '^[[:space:]]+kafkaAddr:[[:space:]]*"0\.0\.0\.0:'"$KAFKA_PORT"'"' "$VALUES" \
  || fail "$VALUES must ship config.kafkaAddr on port $KAFKA_PORT"
grep -Eq '^[[:space:]]+httpAddr:[[:space:]]*"0\.0\.0\.0:'"$HTTP_PORT"'"' "$VALUES" \
  || fail "$VALUES must ship config.httpAddr on port $HTTP_PORT"
grep -Eq '^[[:space:]]+interBrokerPort:[[:space:]]*'"$INTER_BROKER_PORT" "$VALUES" \
  || fail "$VALUES must ship config.interBrokerPort: $INTER_BROKER_PORT"

# The NetworkPolicy default must allow exactly the ports the workload serves.
netpol_ports="$(awk '
  /^networkPolicy:/ { inside = 1; next }
  inside && /^[^[:space:]#]/ { inside = 0 }
  inside && /^[[:space:]]+- port:/ { gsub(/[^0-9]/, "", $0); print }
' "$VALUES" | sort -u | tr '\n' ' ')"
[ "$netpol_ports" = "$KAFKA_PORT $HTTP_PORT " ] \
  || fail "$VALUES networkPolicy.ingress must allow exactly $KAFKA_PORT and $HTTP_PORT (found: ${netpol_ports:-none})"

# ---------------------------------------------------------------------------
# 4. Templates and raw manifests use the same fixed numbers
# ---------------------------------------------------------------------------
for port in "$KAFKA_PORT" "$INTER_BROKER_PORT" "$HTTP_PORT"; do
  grep -Eq "containerPort: $port" "$STS" \
    || fail "$STS must declare containerPort $port"
done
grep -Fq 'targetPort: kafka' "$SVC" \
  || fail "$SVC must target the named kafka port, so the container port stays authoritative"
grep -Fq 'targetPort: http' "$SVC" \
  || fail "$SVC must target the named http port"

# Probes address the named port, never a number that could drift.
for probe in livenessProbe readinessProbe startupProbe; do
  awk -v probe="^${probe}:" '
    $0 ~ probe { inside = 1; next }
    inside && /^[^[:space:]#]/ { inside = 0 }
    inside && /port:[[:space:]]*http/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$VALUES" || fail "$VALUES $probe must target the named http port"
done

# Listener-facing ports only. Egress rules legitimately name DNS (53) and
# HTTPS (443); it is what the workload *serves* that has to stay fixed.
check_manifest_ports() {
  # check_manifest_ports <file> <port list on stdin>
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    case "$port" in
      "$KAFKA_PORT"|"$INTER_BROKER_PORT"|"$HTTP_PORT") ;;
      *) fail "$1 serves port $port; the raw manifests must stay on $KAFKA_PORT/$INTER_BROKER_PORT/$HTTP_PORT like the chart" ;;
    esac
  done
}

if [ -f k8s/statefulset.yaml ]; then
  check_manifest_ports k8s/statefulset.yaml \
    < <(grep -oE 'containerPort:[[:space:]]*[0-9]+' k8s/statefulset.yaml | grep -oE '[0-9]+$' || true)
fi

if [ -f k8s/service.yaml ]; then
  check_manifest_ports k8s/service.yaml \
    < <(grep -oE '(port|targetPort):[[:space:]]*[0-9]+' k8s/service.yaml | grep -oE '[0-9]+$' || true)
fi

if [ -f k8s/networkpolicy.yaml ]; then
  check_manifest_ports "k8s/networkpolicy.yaml (ingress)" \
    < <(awk '
      /^[[:space:]]+ingress:/ { inside = 1; next }
      inside && /^[[:space:]]+egress:/ { inside = 0 }
      inside && /port:[[:space:]]*[0-9]+/ { gsub(/[^0-9]/, "", $0); print }
    ' k8s/networkpolicy.yaml || true)
fi

# ---------------------------------------------------------------------------
# 5. The documentation says the ports are fixed
# ---------------------------------------------------------------------------
for doc in README.md helm/README.md; do
  [ -f "$doc" ] || continue
  grep -Eqi 'fixed at 9092|fixed at 9094|ports are fixed|Fixed \(9092\)|Fixed .9092' "$doc" \
    || fail "$doc must document that the listener ports are fixed, so nobody sets one expecting it to work"
done

if [ "$status" -eq 0 ]; then
  echo "listener-port gate passed: 9092/9094 fixed in schema, templates, manifests and docs"
fi

exit "$status"
