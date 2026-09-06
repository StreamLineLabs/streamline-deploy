#!/usr/bin/env bash
# Static gate: every Prometheus metric referenced by a deployment artifact must
# be listed in monitoring/METRICS.md with a verification status.
#
# Audit finding DEP-D-1: dashboards and alerts reference metric names that core
# may never emit, producing empty panels and alerts that cannot fire. The names
# cannot be corrected from this repository alone, so the contract file records
# them explicitly and this gate stops new undocumented drift.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTRACT="monitoring/METRICS.md"
SCAN_DIRS=(monitoring grafana helm/streamline/templates k8s)

[ -f "$CONTRACT" ] || { echo "FAIL: $CONTRACT is missing" >&2; exit 1; }

referenced="$(grep -rhoE 'streamline_[a-z0-9_]+' "${SCAN_DIRS[@]}" \
  --exclude="$(basename "$CONTRACT")" | sort -u)"

# Only the rows of the "Referenced metrics" table count as documentation; the
# "conflicting variants" prose lists the same names on purpose.
# shellcheck disable=SC2016  # matches the literal markdown table cell
documented="$(sed -n '/^## Referenced metrics/,/^## Non-Streamline/p' "$CONTRACT" \
  | grep -oE '^\| `streamline_[a-z0-9_]+`' \
  | tr -d '|` ' | sort -u)"

status=0

missing="$(comm -23 <(printf '%s\n' "$referenced") <(printf '%s\n' "$documented"))"
if [ -n "$missing" ]; then
  echo "FAIL: metrics referenced by deployment artifacts but absent from $CONTRACT:" >&2
  printf '  %s\n' "$missing" >&2
  status=1
fi

stale="$(comm -13 <(printf '%s\n' "$referenced") <(printf '%s\n' "$documented"))"
if [ -n "$stale" ]; then
  echo "FAIL: metrics documented in $CONTRACT but no longer referenced:" >&2
  printf '  %s\n' "$stale" >&2
  status=1
fi

# Every documented metric needs an explicit status so "unverified" can never be
# silently dropped from a row.
while IFS= read -r metric; do
  [ -n "$metric" ] || continue
  row="$(grep -F "| \`${metric}\` |" "$CONTRACT" | head -n 1)"
  case "$row" in
    *"| unverified |"|*"| emitted |"|*"| missing |") ;;
    *)
      echo "FAIL: $metric has no verification status (expected unverified/emitted/missing)" >&2
      status=1
      ;;
  esac
done <<<"$documented"

if [ "$status" -eq 0 ]; then
  count="$(printf '%s\n' "$documented" | grep -c . || true)"
  echo "metrics contract passed ($count metrics documented)"
fi
exit "$status"
