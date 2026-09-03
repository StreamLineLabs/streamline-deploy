#!/usr/bin/env bash
# Static gate: exactly one workflow may publish container images, and it must
# publish immutable tags built from an explicit core checkout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKFLOWS=".github/workflows"
PUBLISHER="$WORKFLOWS/docker-publish.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- Exactly one publisher ---------------------------------------------------
publishers=()
for wf in "$WORKFLOWS"/*.yml; do
  if grep -Fq 'push: true' "$wf"; then
    publishers+=("$wf")
  fi
done

if [ "${#publishers[@]}" -ne 1 ]; then
  fail "expected exactly one image-publishing workflow, found: ${publishers[*]:-none}"
fi

if [ "${publishers[0]}" != "$PUBLISHER" ]; then
  fail "the designated publisher is $PUBLISHER but ${publishers[0]} pushes images"
fi

# --- The publisher serializes tag writes ------------------------------------
grep -Eq '^concurrency:' "$PUBLISHER" \
  || fail "$PUBLISHER must declare a concurrency group so tag writes cannot race"

# --- Mutable tags are never published from branch pushes --------------------
if grep -Fq 'is_default_branch' "$PUBLISHER"; then
  fail "$PUBLISHER must not publish 'latest' from branch pushes"
fi

if grep -Eq '^\s+branches: \[main\]' "$PUBLISHER"; then
  fail "$PUBLISHER must publish from release tags only, not branch pushes"
fi

# --- The publisher builds from an explicit, verified core checkout ----------
grep -Fq 'repository: streamlinelabs/streamline' "$PUBLISHER" \
  || fail "$PUBLISHER must check out the Streamline core repository explicitly"
grep -Fq 'prepare-core-context.sh --print-ref' "$PUBLISHER" \
  || fail "$PUBLISHER must resolve the core commit from core-source.env"
# shellcheck disable=SC2016  # the workflow literally contains ${{ env.CORE_CONTEXT }}
grep -Fq 'context: ${{ env.CORE_CONTEXT }}' "$PUBLISHER" \
  || fail "$PUBLISHER must build from the prepared core context"
grep -Fq 'was pinned' "$PUBLISHER" \
  || fail "$PUBLISHER must verify the checkout matches the pinned commit"

# --- Dispatch inputs never reach a shell as an expression -------------------
# `${{ inputs.* }}` inside `run:` is substituted before the shell parses the
# script, so an input containing shell metacharacters executes as code. Inputs
# must be passed through `env:` and referenced as ordinary shell variables.
if awk '
  /^[[:space:]]*run:[[:space:]]*\|/ { in_run = 1; indent = match($0, /[^ ]/); next }
  in_run && /[^[:space:]]/ && match($0, /[^ ]/) <= indent { in_run = 0 }
  in_run && /\$\{\{[[:space:]]*(inputs|github\.event\.inputs)\./ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$PUBLISHER"; then
  fail "$PUBLISHER interpolates a workflow input into a run script; pass it through env: instead"
fi
grep -Fq 'CORE_REF_INPUT' "$PUBLISHER" \
  || fail "$PUBLISHER must pass the core_ref dispatch input through the environment"

# --- Deployment artifacts point at the registry the publisher writes to -----
# The publisher pushes ghcr.io tags only. A compose file or manifest that names
# a Docker Hub image sends users to a tag nobody publishes.
REGISTRY="$(grep -E '^\s+REGISTRY:' "$PUBLISHER" | head -1 | awk '{print $2}')"
[ "$REGISTRY" = "ghcr.io" ] \
  || fail "$PUBLISHER publishes to '$REGISTRY'; this gate assumes ghcr.io"

offenders="$(grep -rnE \
  '^[[:space:]-]*image:[[:space:]]*"?(\$\{[A-Za-z_][A-Za-z0-9_]*:-)?(docker\.io/)?streamlinelabs/' \
  --include='*.yml' --include='*.yaml' --exclude-dir=.git . || true)"
if [ -n "$offenders" ]; then
  fail "image references must use $REGISTRY/streamlinelabs/, the only registry $PUBLISHER pushes to:
$offenders"
fi

if grep -rniE 'docker[ -]?hub|docker\.io/streamlinelabs' \
  --include='*.yml' --include='*.yaml' --exclude-dir=.git . ; then
  fail "deployment artifacts must not advertise Docker Hub images; the project publishes to $REGISTRY only"
fi

# --- Release workflow packages the chart and publishes nothing --------------
RELEASE="$WORKFLOWS/release.yml"
for forbidden in 'build-push-action' 'docker/login-action' 'helm push' 'chart-releaser'; do
  if grep -Fq "$forbidden" "$RELEASE"; then
    fail "$RELEASE must not publish artifacts (found: $forbidden)"
  fi
done
grep -Fq 'helm package' "$RELEASE" \
  || fail "$RELEASE must package the Helm chart"
grep -Fq 'upload-artifact' "$RELEASE" \
  || fail "$RELEASE must attach the packaged chart to the workflow run"

echo "workflow-publisher gate passed"
