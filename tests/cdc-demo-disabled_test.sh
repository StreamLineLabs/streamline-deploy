#!/usr/bin/env bash
# Static gate: the CDC demo stays disabled, and its routes stay out of the docs.
#
# The demo told readers to POST a source definition to `/api/v1/cdc/sources`,
# start it at `/api/v1/cdc/sources/<name>/start`, read messages back from a
# partition path and query them through `/sql`. Every one of those came from
# documentation rather than from a server anyone ran here, and the capabilities
# behind them (`cdc`, `analytics`) are compile-time cargo features that no
# published image is built with. Pasting those commands against the image the
# stack actually started produced 404s that looked like user error.
#
# Nothing in this repository can verify the pipeline, so the demo is disabled
# rather than "documented with caveats": every service sits behind the
# `disabled` Compose profile, the Streamline image default is an unpullable
# local-only placeholder, and demos/cdc-demo.sh exits non-zero. This gate keeps
# the runnable instructions from coming back before the proof does.
#
# Hermetic: text inspection plus running the (container-free) demo script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

COMPOSE=docker-compose.cdc-demo.yml
SCRIPT=demos/cdc-demo.sh
PROFILE=disabled

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

config_lines() {
  grep -vE '^[[:space:]]*#' "$1"
}

[ -f "$COMPOSE" ] || { echo "FAIL: $COMPOSE is missing" >&2; exit 1; }
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Every service is behind the disabled profile
# ---------------------------------------------------------------------------
services="$(awk '
  /^services:/ { inside = 1; next }
  inside && /^[^[:space:]#]/ { inside = 0 }
  inside && /^  [a-zA-Z0-9_-]+:/ { gsub(/[ :]/, "", $0); print }
' "$COMPOSE")"
[ -n "$services" ] || fail "$COMPOSE declares no services"

for service in $services; do
  if ! awk -v svc="  $service:" -v profile="$PROFILE" '
    $0 == svc { inside = 1; next }
    inside && /^  [a-zA-Z0-9_-]+:/ { inside = 0 }
    inside && /profiles:/ && $0 ~ profile { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$COMPOSE"; then
    fail "$COMPOSE service '$service' is not behind the '$PROFILE' profile; \`docker compose up\` must select nothing"
  fi
done

# ---------------------------------------------------------------------------
# 2. No runnable default image, and no way to build one from this repository
# ---------------------------------------------------------------------------
image_refs="$(config_lines "$COMPOSE" | grep -E '^[[:space:]]*image:.*[Ss]treamline' || true)"
[ -n "$image_refs" ] || fail "$COMPOSE declares no Streamline image"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  ref="$(printf '%s' "${line#*image:}" | tr -d ' "')"
  case "$ref" in
    "\${STREAMLINE_CDC_IMAGE"*) ;;
    *) fail "$COMPOSE must take its Streamline image from \${STREAMLINE_CDC_IMAGE}, found '$ref'" ;;
  esac
  default="${ref#*:-}"
  default="${default%\}}"
  case "$default" in
    "$ref") fail "$COMPOSE uses \${STREAMLINE_CDC_IMAGE} with no default; \`docker compose config\` must stay valid with no environment set" ;;
    */*) fail "$COMPOSE defaults to '$default', a pullable registry reference; the default must be local-only and unpullable" ;;
    *ghcr.io*|*streamlinelabs*) fail "$COMPOSE defaults to a published image ('$default')" ;;
  esac
done <<EOF
$image_refs
EOF

if config_lines "$COMPOSE" | grep -Eq '^[[:space:]]*build:'; then
  fail "$COMPOSE must not build an image from this repository, which ships no Streamline core sources"
fi

# The header must say it is disabled and why, or "fails closed" is just broken.
grep -Fq 'DISABLED' "$COMPOSE" \
  || fail "$COMPOSE must state that the demo is disabled"
grep -Fq 'compile-time' "$COMPOSE" \
  || fail "$COMPOSE must state that cdc/analytics are compile-time cargo features"
grep -Eq 'unverified|not verified' "$COMPOSE" \
  || fail "$COMPOSE must state that the pipeline is unverified"

# ---------------------------------------------------------------------------
# 3. The entry point fails closed and touches nothing
# ---------------------------------------------------------------------------
[ -x "$SCRIPT" ] || fail "$SCRIPT must be executable"
if config_lines "$SCRIPT" | grep -Eq 'docker (compose|run|start)|curl '; then
  fail "$SCRIPT must not start containers or issue requests; it exists to explain why the demo is disabled"
fi
if bash "$SCRIPT" >/dev/null 2>&1; then
  fail "$SCRIPT exited 0; a disabled demo must fail closed"
fi
message="$(bash "$SCRIPT" 2>&1 >/dev/null || true)"
case "$message" in
  *disabled*) ;;
  *) fail "$SCRIPT must say the demo is disabled, got: $message" ;;
esac

# ---------------------------------------------------------------------------
# 4. No artifact presents the unverified CDC/StreamQL surface as runnable
# ---------------------------------------------------------------------------
# A route named inside a caveat ("unverified", "do not rely on") is documentation
# about the gap. A route inside a command is an instruction, and instructions
# get pasted.
RUNNABLE_RE='(curl|http|wget|POST|GET)[^|]*((/api/v1/cdc/sources)|(/sql))|(/api/v1/cdc/sources)[^|]*(curl|-X|--data|-d )'

while IFS= read -r f; do
  case "$f" in
    ./CHANGELOG.md|./tests/*|./cdc-demo/README.md) continue ;;
  esac
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    fail "$f:$match presents an unverified CDC/StreamQL endpoint as a runnable instruction"
  done < <(grep -nE "$RUNNABLE_RE" "$f" || true)
done < <(find . -path ./.git -prune -o -path ./.build -prune -o -type f \
  \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sh' \) -print | sort)

# Runtime feature variables are the other half of the same lie: core reads no
# STREAMLINE_FEATURES, so an environment entry cannot switch cdc on.
if config_lines "$COMPOSE" | grep -Eq 'STREAMLINE_FEATURES|STREAMLINE_(CDC|ANALYTICS)_ENABLED'; then
  fail "$COMPOSE sets a runtime feature variable; cdc/analytics are compile-time cargo features"
fi

# ---------------------------------------------------------------------------
# 5. The docs describe a disabled demo, not a working pipeline
# ---------------------------------------------------------------------------
if grep -Fq 'cdc-demo' README.md; then
  if ! grep -Eqi 'CDC demo.*disabled|disabled.*CDC' README.md; then
    fail "README.md mentions the CDC demo without saying it is disabled"
  fi
fi
grep -Fq 'cdc-demo.sh' README.md \
  || fail "README.md must point at $SCRIPT, the entry point that explains the demo is disabled"

if [ "$status" -eq 0 ]; then
  echo "cdc-demo gate passed: stack disabled by profile and placeholder, no runnable route instructions"
fi

exit "$status"
