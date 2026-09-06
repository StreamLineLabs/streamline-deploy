#!/usr/bin/env bash
# Static gate: a demo may not promise features its image cannot have.
#
# Streamline core takes its optional capabilities as compile-time cargo
# features. It reads no STREAMLINE_FEATURES variable, so a feature name in a
# container's `environment:` is decoration on a server that ignores it — the
# endpoints the demo drives still do not exist. Two stacks shipped exactly that:
#
#   1. docker-compose.moonshot-demo.yml defaulted to the published tag and set
#      STREAMLINE_FEATURES=<moonshot features>.
#   2. docker-compose.cdc-demo.yml defaulted to the published tag and set
#      STREAMLINE_FEATURES=cdc,analytics, so `up` started a stock server whose
#      /api/v1/cdc/sources and /sql endpoints 404.
#
# docker-compose.edge.yml was a third variant of the same lie, one step worse:
# it defaulted to ghcr.io/streamlinelabs/streamline-edge:0.3.0 and called it
# "a published image", but the sole publisher builds `Dockerfile` and pushes
# ghcr.io/streamlinelabs/streamline only — that edge tag has never been built or
# pushed by anything in this repository.
#
# Two of those stacks have since left this table for a stronger reason than
# fail-closed defaults, and are covered by their own gates:
#
#   * the edge stack is gone entirely — its runtime (MQTT on 1883,
#     store-and-forward, cloud sync) is unverified against core, so there is no
#     stack to gate (tests/edge-unsupported_test.sh);
#   * the CDC demo is disabled behind a Compose profile because its routes and
#     payloads were never exercised (tests/cdc-demo-disabled_test.sh).
#
# The single publisher (.github/workflows/docker-publish.yml) builds
# STREAMLINE_FEATURES=full, documented here as SASL auth and clustering, so no
# published tag can be assumed to carry a demo's features.
#
# This gate therefore enforces two things:
#
#   A. Repo-wide — no Compose stack may claim features through the environment.
#      This catches a runtime feature variable in *any* stack, including ones
#      added after this test.
#   B. Per feature-gated demo — the stack must fail closed: its Streamline image
#      comes from an explicitly supplied variable whose default is local-only
#      and unpullable, it cannot build the image here, and its header says which
#      compile-time features the image needs and how to build one. The features
#      are cross-checked against the Dockerfile that produces the image, so a
#      row cannot drift away from the build it claims to document.
#
# tests/moonshot-demo_test.sh keeps the moonshot-specific claim checks; this
# file is the shared, extensible gate. Add a row to FEATURE_GATED_DEMOS when a
# new feature-gated demo appears.
#
# The placeholder defaults have to stay parseable, because `make compose-config`
# validates every stack with no environment set and must not pull or run.
#
# Hermetic: pure text inspection, no registry, network, docker or compose.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=tests/oci-image-reference-lib.sh
source "$REPO_ROOT/tests/oci-image-reference-lib.sh"

# compose file | image variable | cargo features the image must be built with |
#   Dockerfile that produces it
FEATURE_GATED_DEMOS=(
  "docker-compose.moonshot-demo.yml|STREAMLINE_MOONSHOT_IMAGE|moonshot|Dockerfile"
)

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

# Everything that is not a `#` comment: claims the runtime actually acts on.
config_lines() {
  grep -vE '^[[:space:]]*#' "$1"
}

# ---------------------------------------------------------------------------
# A. No Compose stack may claim features through the environment
# ---------------------------------------------------------------------------
# STREAMLINE_FEATURES is a build arg (see Dockerfile); the per-feature toggles
# below never existed at run time either. Any of them outside a comment
# describes a capability the running server does not gain.
RUNTIME_CLAIM_RE='STREAMLINE_FEATURES|STREAMLINE_(CDC|ANALYTICS|SEMANTIC_TOPICS|AGENT_MEMORY|ATTESTATION|BRANCHES)_ENABLED'

shopt -s nullglob
compose_files=(docker-compose*.yml)
shopt -u nullglob
[ "${#compose_files[@]}" -gt 0 ] || { echo "FAIL: no docker-compose*.yml found" >&2; exit 1; }

for compose in "${compose_files[@]}"; do
  offenders="$(config_lines "$compose" | grep -nE "$RUNTIME_CLAIM_RE" || true)"
  if [ -n "$offenders" ]; then
    fail "$compose sets a runtime feature variable; Streamline features are compile-time cargo features and core reads no such variable:
$offenders"
  fi
done

# ---------------------------------------------------------------------------
# B. Every feature-gated demo fails closed
# ---------------------------------------------------------------------------
for row in "${FEATURE_GATED_DEMOS[@]}"; do
  IFS='|' read -r compose image_var features dockerfile <<<"$row"

  if [ ! -f "$compose" ]; then
    fail "$compose is missing; remove its row from FEATURE_GATED_DEMOS if the demo was dropped"
    continue
  fi

  # -- No runnable default image ------------------------------------------
  # Only Streamline's own image is feature-gated; third-party services
  # (postgres, grafana, …) are pulled as published.
  image_refs="$(config_lines "$compose" | grep -E '^[[:space:]]*image:.*[Ss]treamline' || true)"
  [ -n "$image_refs" ] || fail "$compose declares no Streamline image"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ref="${line#*image:}"
    ref="$(printf '%s' "$ref" | tr -d ' "')"

    case "$ref" in
      "\${$image_var"*) ;;
      *) fail "$compose must take its Streamline image from \${$image_var}, found '$ref'; a fixed image cannot be known to carry the $features features" ;;
    esac

    # The default is what runs when a user copies the command from the README.
    default="${ref#*:-}"
    default="${default%\}}"
    case "$default" in
      "$ref")
        fail "$compose uses \${$image_var} with no default; \`docker compose config\` must stay valid with no environment set" ;;
      */*)
        fail "$compose defaults to '$default', which is a pullable registry reference; no published tag is built with the $features features, so the default must be local-only" ;;
    esac
    case "$default" in
      *ghcr.io*|*streamlinelabs*|*docker.io*)
        fail "$compose defaults to the published image '$default', which is built with STREAMLINE_FEATURES=full and cannot be assumed to carry the $features features" ;;
    esac
    if oci_is_generic_streamline_core_image "$default"; then
      fail "$compose defaults to generic core image '$OCI_IMAGE_REFERENCE' (repository key '$OCI_IMAGE_COMPARISON_KEY'); use a feature-specific image name so tag@digest aliases cannot disguise the stock build"
    else
      image_policy_status=$?
      if [ "$image_policy_status" -eq 2 ]; then
        fail "$compose has invalid Streamline image reference '$OCI_IMAGE_REFERENCE': $OCI_IMAGE_PARSE_ERROR"
      fi
    fi
  done <<<"$image_refs"

  # A `build:` stanza would be the other way to produce an image, and it cannot
  # work: the core-compiling Dockerfiles need the prepared core context, which
  # this repository does not contain.
  if config_lines "$compose" | grep -Eq '^[[:space:]]*build:'; then
    fail "$compose must not build an image from this repository, which ships no Streamline core sources"
  fi

  # -- The header tells the reader how to get a real image -----------------
  # Fail-closed is only usable if the file says what "closed" means and how to
  # open it deliberately.
  [ -f "$dockerfile" ] \
    || fail "$compose is gated on an image built from $dockerfile, which this repository does not contain"
  grep -Fq -e "-f $dockerfile .build/core" "$compose" \
    || fail "$compose must document the build that produces its image (docker build -f $dockerfile .build/core)"

  # How the features are selected differs per image, so check against the
  # Dockerfile rather than assuming one convention: the official image takes the
  # list as a build arg, the edge appliance compiles a fixed list. Deriving this
  # keeps a row from documenting a build flag its Dockerfile does not have.
  if grep -Eq '^ARG STREAMLINE_FEATURES' "$dockerfile"; then
    grep -Fq -e "--build-arg STREAMLINE_FEATURES=$features" "$compose" \
      || fail "$compose must document building the image with the cargo features it needs (--build-arg STREAMLINE_FEATURES=$features)"
  else
    grep -Fq -e "--features \"$features\"" "$dockerfile" \
      || fail "$dockerfile takes no STREAMLINE_FEATURES build arg and does not compile --features \"$features\"; point this row at the features it really builds"
    grep -Fq "$features" "$compose" \
      || fail "$compose must name the compile-time features its image is built with ($features), since $dockerfile fixes them at build time"
  fi
  grep -Fq 'prepare-core-context.sh' "$compose" \
    || fail "$compose must document preparing the pinned core context the image is built from"
  grep -Fq 'compile-time' "$compose" \
    || fail "$compose must state that these features are compile-time, so nobody re-adds a runtime toggle"
  grep -Eq 'No published tag|no published tag' "$compose" \
    || fail "$compose must state that no published tag carries these features, so nobody re-points it at the released image"

  # -- The documented way to run it is discoverable ------------------------
  grep -Fq "$image_var" README.md \
    || fail "README.md must document $image_var; the demo cannot be started without it"
done

if [ "$status" -eq 0 ]; then
  echo "feature-gated demo gate passed: no runtime feature claims in any stack, no runnable default images"
fi

exit "$status"
