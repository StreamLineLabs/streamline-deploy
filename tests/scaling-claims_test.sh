#!/usr/bin/env bash
# Static gate: the deployment artifacts must describe exactly one broker, and
# the raw manifests must configure the settings core does not default safely.
#
# Two failure modes this repository shipped before:
#
#   1. k8s/configmap.yaml omitted STREAMLINE_AUTO_CREATE_TOPICS. Core enables
#      auto topic creation by default, so leaving the key out silently deploys
#      a broker that creates topics on first produce.
#   2. The Helm chart and the raw manifests refused / documented single-broker
#      operation, while an HPA, a KEDA ScaledObject or a `kubectl scale` snippet
#      in the docs told users to run several. Those extra pods are independent
#      brokers with their own data, not an HA cluster.
#
# Hermetic: pure text inspection, no cluster, registry, network or helm binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

# Text that makes an unsupported example unmistakable to a reader.
UNSUPPORTED_RE='UNSUPPORTED|[Uu]nsupported|not supported|never|do not|Do not|DO NOT'

# ---------------------------------------------------------------------------
# 1. Raw manifests must set the settings core does not default safely
# ---------------------------------------------------------------------------
CONFIGMAP=k8s/configmap.yaml
[ -f "$CONFIGMAP" ] || fail "$CONFIGMAP is missing"

if [ -f "$CONFIGMAP" ]; then
  # Must be an active data key, not a commented-out suggestion.
  if ! grep -Eq '^[[:space:]]+STREAMLINE_AUTO_CREATE_TOPICS:[[:space:]]*"(true|false)"' "$CONFIGMAP"; then
    fail "$CONFIGMAP must set STREAMLINE_AUTO_CREATE_TOPICS explicitly (quoted \"true\"/\"false\"): core enables auto topic creation by default, so omitting the key deploys a broker that creates topics on first produce"
  elif ! grep -Eq '^[[:space:]]+STREAMLINE_AUTO_CREATE_TOPICS:[[:space:]]*"false"' "$CONFIGMAP"; then
    fail "$CONFIGMAP ships STREAMLINE_AUTO_CREATE_TOPICS enabled; the shipped default must be \"false\" so operators opt in deliberately"
  fi

  # The Helm chart makes the same promise; keep the two in step.
  grep -Fq 'STREAMLINE_AUTO_CREATE_TOPICS' helm/streamline/templates/configmap.yaml \
    || fail "helm/streamline/templates/configmap.yaml must render STREAMLINE_AUTO_CREATE_TOPICS for the same reason as $CONFIGMAP"
fi

# ---------------------------------------------------------------------------
# 2. The raw StatefulSet stays a single standalone broker
# ---------------------------------------------------------------------------
STS=k8s/statefulset.yaml
if [ -f "$STS" ]; then
  grep -Eq '^[[:space:]]*replicas:[[:space:]]*1([[:space:]]|#|$)' "$STS" \
    || fail "$STS must declare replicas: 1 — there is no peer bootstrap, so extra pods are independent brokers"
  if grep -Eiq 'scale (to|up to) [0-9]+|for production cluster|HA cluster' "$STS"; then
    fail "$STS must not advise scaling the standalone broker"
  fi
else
  fail "$STS is missing"
fi

# ---------------------------------------------------------------------------
# 3. No artifact may tell users to run more than one broker
# ---------------------------------------------------------------------------
SCAN_FILES=()
while IFS= read -r f; do
  SCAN_FILES+=("$f")
done < <(find k8s helm docs README.md -type f \
  \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.tpl' -o -name '*.json' \) \
  -not -path 'helm/streamline/tests/*' | sort)

[ "${#SCAN_FILES[@]}" -gt 0 ] || fail "found no deployment artifacts to scan"

# Multi-replica instructions: `--replicas=3`, `replicaCount: 3`, `replicas: 3`,
# `maxReplicas: 5`, ... Each occurrence must be marked unsupported nearby, so a
# rejected example stays readable while a recommendation cannot slip back in.
MULTI_REPLICA_RE='--replicas=[2-9]|replicaCount:[[:space:]]*[2-9]|replicas:[[:space:]]*[2-9]|[Rr]eplicaCount:[[:space:]]*[1-9][0-9]|[Mm]axReplicas:[[:space:]]*[2-9]|(at least|run) [2-9] replicas|[2-9] replicas'

# A marker counts when it stands within the 20 lines above the match, or in the
# file's header comment block — a "DO NOT APPLY" banner covers the manifest it
# heads.
marked_unsupported() {
  local file="$1" lineno="$2" start
  start=$((lineno > 20 ? lineno - 20 : 1))
  sed -n "${start},${lineno}p" "$file" | grep -Eq -e "$UNSUPPORTED_RE" && return 0
  head -n 20 "$file" | grep -Eq -e "$UNSUPPORTED_RE"
}

for f in "${SCAN_FILES[@]}"; do
  while IFS=: read -r lineno _; do
    [ -n "${lineno:-}" ] || continue
    if ! marked_unsupported "$f" "$lineno"; then
      fail "$f:$lineno recommends more than one broker without marking it unsupported (no peer bootstrap: extra pods are independent brokers, not a cluster)"
    fi
  done < <(grep -nE -e "$MULTI_REPLICA_RE" "$f" || true)
done

# Outright HA claims have no qualified form while there is one broker.
for f in "${SCAN_FILES[@]}"; do
  while IFS=: read -r lineno line; do
    [ -n "${lineno:-}" ] || continue
    printf '%s' "$line" | grep -Eq -e "$UNSUPPORTED_RE|not HA|no clustering|not high availability" \
      || fail "$f:$lineno claims high availability, which a single standalone broker cannot provide"
  done < <(grep -nEi 'high availability|HA cluster|HA during' "$f" || true)
done

# ---------------------------------------------------------------------------
# 4. Autoscalers must fail the Helm render rather than scale the StatefulSet
# ---------------------------------------------------------------------------
HELPERS=helm/streamline/templates/_helpers.tpl
if [ -f "$HELPERS" ]; then
  grep -Fq 'define "streamline.rejectUnsupportedAutoscaling"' "$HELPERS" \
    || fail "$HELPERS must define streamline.rejectUnsupportedAutoscaling"
  grep -Fq 'include "streamline.rejectUnsupportedAutoscaling"' "$HELPERS" \
    || fail "$HELPERS must call streamline.rejectUnsupportedAutoscaling from streamline.validateConfiguration, or the guard never runs"
  # The guard must name both settings, otherwise one of them stays reachable.
  for setting in autoscaling.enabled keda.enabled; do
    grep -Fq "$setting" "$HELPERS" \
      || fail "$HELPERS must reject $setting until peer bootstrap exists"
  done
else
  fail "$HELPERS is missing"
fi

for tpl in helm/streamline/templates/hpa.yaml helm/streamline/templates/keda-scaledobject.yaml; do
  [ -f "$tpl" ] || continue
  grep -Fq 'include "streamline.validateConfiguration"' "$tpl" \
    || fail "$tpl must include streamline.validateConfiguration so the autoscaler cannot render on its own"
done

VALUES=helm/streamline/values.yaml
if [ -f "$VALUES" ]; then
  for block in autoscaling keda; do
    # `enabled: false` must be the shipped default for both autoscalers.
    if ! awk -v block="^${block}:" '
        $0 ~ block { inblock = 1; next }
        inblock && /^[^[:space:]#]/ { inblock = 0 }
        inblock && /^[[:space:]]+enabled:[[:space:]]*false([[:space:]]|#|$)/ { found = 1 }
        END { exit found ? 0 : 1 }
      ' "$VALUES"; then
      fail "$VALUES must ship ${block}.enabled: false — the chart rejects it at render time"
    fi
  done
  grep -Eq '^replicaCount:[[:space:]]*1([[:space:]]|#|$)' "$VALUES" \
    || fail "$VALUES must ship replicaCount: 1"
fi

# ---------------------------------------------------------------------------
# 5. The optional raw KEDA example must announce that it is unsupported
# ---------------------------------------------------------------------------
if [ -d k8s/keda ]; then
  for f in k8s/keda/*.yaml; do
    [ -f "$f" ] || continue
    grep -Fq 'UNSUPPORTED EXAMPLE' "$f" \
      || fail "$f must be marked 'UNSUPPORTED EXAMPLE' — applying it scales the standalone broker"
  done
  # It must not be wired into the applied base, or `kubectl apply -k k8s/`
  # would autoscale the broker.
  if grep -Eq '^[[:space:]]*-[[:space:]]*keda' k8s/kustomization.yaml; then
    fail "k8s/kustomization.yaml must not include the unsupported keda example"
  fi
  grep -Fq 'k8s/keda' k8s/README.md \
    || fail "k8s/README.md must document k8s/keda/ as unsupported rather than leaving it undescribed"
fi

if [ "$status" -eq 0 ]; then
  echo "PASS: raw config is explicit and no artifact advertises unsupported scaling"
fi

exit "$status"
