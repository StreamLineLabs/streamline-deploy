#!/usr/bin/env bash
# Static gate: the moonshot demo may not promise features its image cannot have.
#
# Two failure modes this stack shipped before:
#
#   1. It defaulted to the published tag (ghcr.io/streamlinelabs/streamline) and
#      claimed a "full-edition image built with the moonshot features" supplied
#      them. The single publisher builds STREAMLINE_FEATURES=full — SASL auth
#      and clustering — so `docker compose up` silently started a stock server
#      with none of the features the demo advertises.
#   2. It set STREAMLINE_FEATURES in the container environment. The moonshot
#      features are compile-time cargo features; core reads no such variable,
#      so the setting was decoration on a server that ignored it.
#
# The stack must therefore fail closed: no runnable default image, an explicitly
# supplied one built with the features, and no runtime feature claims. The
# placeholder default has to stay parseable, because `make compose-config`
# validates every stack with no environment set and must not pull or run.
#
# Hermetic: pure text inspection, no registry, network, docker or compose.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=tests/oci-image-reference-lib.sh
source "$REPO_ROOT/tests/oci-image-reference-lib.sh"

COMPOSE=docker-compose.moonshot-demo.yml
IMAGE_VAR=STREAMLINE_MOONSHOT_IMAGE

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

[ -f "$COMPOSE" ] || { echo "FAIL: $COMPOSE is missing" >&2; exit 1; }

# Everything that is not a `#` comment: claims the runtime actually acts on.
config_lines() {
  grep -vE '^[[:space:]]*#' "$COMPOSE"
}

# ---------------------------------------------------------------------------
# 1. No runnable default image
# ---------------------------------------------------------------------------
image_refs="$(config_lines | grep -E '^[[:space:]]*image:' || true)"
[ -n "$image_refs" ] || fail "$COMPOSE declares no image"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  ref="${line#*image:}"
  ref="$(printf '%s' "$ref" | tr -d ' "')"

  case "$ref" in
    "\${$IMAGE_VAR"*) ;;
    *) fail "$COMPOSE must take its image from \${$IMAGE_VAR}, found '$ref'; a fixed image cannot be known to carry the moonshot features" ;;
  esac

  # The default is what runs when a user copies the command from the README.
  default="${ref#*:-}"
  default="${default%\}}"
  case "$default" in
    "$ref")
      fail "$COMPOSE uses \${$IMAGE_VAR} with no default; \`docker compose config\` must stay valid with no environment set" ;;
    */*)
      fail "$COMPOSE defaults to '$default', which is a pullable registry reference; no published tag is built with the moonshot features, so the default must be local-only" ;;
  esac
  case "$default" in
    *ghcr.io*|*streamlinelabs*|*docker.io*)
      fail "$COMPOSE defaults to the published image '$default', which is built with STREAMLINE_FEATURES=full and has no moonshot features" ;;
  esac
  if oci_is_generic_streamline_core_image "$default"; then
    fail "$COMPOSE defaults to generic core image '$OCI_IMAGE_REFERENCE' (repository key '$OCI_IMAGE_COMPARISON_KEY'); use a moonshot-specific image name so tag@digest aliases cannot disguise the stock build"
  else
    image_policy_status=$?
    if [ "$image_policy_status" -eq 2 ]; then
      fail "$COMPOSE has invalid image reference '$OCI_IMAGE_REFERENCE': $OCI_IMAGE_PARSE_ERROR"
    fi
  fi
done <<<"$image_refs"

# A `build:` stanza would be the other way to produce an image, and it cannot
# work: the core-compiling Dockerfiles need the prepared core context, which
# this repository does not contain.
if config_lines | grep -Eq '^[[:space:]]*build:'; then
  fail "$COMPOSE must not build an image from this repository, which ships no Streamline core sources"
fi

# ---------------------------------------------------------------------------
# 2. No runtime feature claims
# ---------------------------------------------------------------------------
# Core takes these features at compile time only. Any of them in `environment:`
# describes a capability the running server does not gain.
RUNTIME_CLAIM_RE='STREAMLINE_FEATURES|STREAMLINE_(SEMANTIC_TOPICS|AGENT_MEMORY|ATTESTATION|BRANCHES)'
offenders="$(config_lines | grep -nE "$RUNTIME_CLAIM_RE" || true)"
if [ -n "$offenders" ]; then
  fail "$COMPOSE sets a runtime feature variable; the moonshot features are compile-time cargo features and core reads no such variable:
$offenders"
fi

# ---------------------------------------------------------------------------
# 3. The header tells the reader how to get a real moonshot image
# ---------------------------------------------------------------------------
# Fail-closed is only usable if the file says what "closed" means and how to
# open it deliberately.
grep -Fq 'STREAMLINE_FEATURES=moonshot' "$COMPOSE" \
  || fail "$COMPOSE must document building the image with the moonshot cargo feature (--build-arg STREAMLINE_FEATURES=moonshot)"
grep -Fq 'STREAMLINE_EDITION=custom' "$COMPOSE" \
  || fail "$COMPOSE must use STREAMLINE_EDITION=custom for the non-full moonshot feature list"
grep -Fq 'STREAMLINE_CAPABILITIES=moonshot' "$COMPOSE" \
  || fail "$COMPOSE must declare the moonshot capability for the custom image"
grep -Fq 'prepare-core-context.sh' "$COMPOSE" \
  || fail "$COMPOSE must document preparing the pinned core context the image is built from"
grep -Fq 'compile-time' "$COMPOSE" \
  || fail "$COMPOSE must state that the moonshot features are compile-time, so nobody re-adds a runtime toggle"
grep -Eq 'No published tag|no published tag' "$COMPOSE" \
  || fail "$COMPOSE must state that no published tag carries these features, so nobody re-points it at the released image"

# The edition alone must never be presented as sufficient: `full` advertises
# auth and clustering only.
if grep -Eq 'full[- ]edition image built with the moonshot|STREAMLINE_EDITION=full([^[:alnum:]_]|$)' "$COMPOSE"; then
  fail "$COMPOSE claims STREAMLINE_EDITION=full supplies the moonshot features; the full edition covers auth and clustering only"
fi

# ---------------------------------------------------------------------------
# 4. The documented way to run it is discoverable
# ---------------------------------------------------------------------------
grep -Fq "$IMAGE_VAR" README.md \
  || fail "README.md must document $IMAGE_VAR; the demo cannot be started without it"

if [ "$status" -eq 0 ]; then
  echo "moonshot-demo gate passed: no runnable default image, no runtime feature claims"
fi

exit "$status"
