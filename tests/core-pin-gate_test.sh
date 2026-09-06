#!/usr/bin/env bash
# Static gate: an unpinned core commit must make the image gates FAIL, not skip.
#
# `core-source.env` carries no commit yet, on purpose — this repository ships no
# Streamline core sources and nobody has chosen the commit the first image is
# built from. The dangerous part is not the empty pin; it is what CI does with
# it. The image-build job used to swallow the resolver's exit status
# (`if ref="$(… --print-ref 2>/dev/null)"`), set `pinned=false`, emit a
# `::notice::` and then guard every following step with
# `if: steps.core.outputs.pinned == 'true'`. The job went green. A green image
# gate on a repository that cannot build an image is worse than no gate: it
# reports that the Dockerfile still compiles the pinned tree and that the image
# passes its smoke test, and neither statement was ever evaluated.
#
# So: while the pin is empty, the image build/smoke/release gate must be RED.
# The resolver runs unguarded, its failure propagates, and no conditional,
# `continue-on-error` or `|| true` may make the job survive it.
#
# Hermetic: text inspection plus the repository's own resolver script. No
# network, registry, docker or GitHub Actions runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CI=".github/workflows/ci.yml"
PUBLISHER=".github/workflows/docker-publish.yml"
RESOLVER="scripts/prepare-core-context.sh"
PIN_FILE="core-source.env"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

# Print the body of a top-level job (two-space indented key under `jobs:`).
job_block() {
  # job_block <workflow> <job name>
  awk -v job="  $2:" '
    $0 == job { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { inside = 0 }
    inside { print }
  ' "$1"
}

for f in "$CI" "$PUBLISHER" "$RESOLVER" "$PIN_FILE"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. The pin itself: empty (fail closed) or an immutable 40-character SHA
# ---------------------------------------------------------------------------
pinned_ref="$(grep -E '^STREAMLINE_CORE_REF=' "$PIN_FILE" | cut -d= -f2- | tr -d '"'"'"' ')"
if [ -n "$pinned_ref" ] && ! printf '%s' "$pinned_ref" | grep -Eq '^[0-9a-f]{40}$'; then
  fail "$PIN_FILE pins '$pinned_ref', which is neither empty nor a 40-character commit SHA"
fi

# ---------------------------------------------------------------------------
# 2. The resolver fails closed, and says why
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_pin() {
  # write_pin <file> <ref>
  printf 'STREAMLINE_CORE_REPO=https://example.invalid/streamline.git\nSTREAMLINE_CORE_REF=%s\n' "$2" > "$1"
}

write_pin "$TMP_DIR/empty.env" ""
if "$RESOLVER" --pin-file "$TMP_DIR/empty.env" --print-ref >/dev/null 2>&1; then
  fail "$RESOLVER must exit non-zero when STREAMLINE_CORE_REF is empty"
fi

for bad in main v0.3.0 abc123 0123456789abcdef0123456789abcdef0123456 0123456789ABCDEF0123456789ABCDEF01234567; do
  write_pin "$TMP_DIR/bad.env" "$bad"
  if "$RESOLVER" --pin-file "$TMP_DIR/bad.env" --print-ref >/dev/null 2>&1; then
    fail "$RESOLVER accepted '$bad', which is not a 40-character lowercase commit SHA"
  fi
done

write_pin "$TMP_DIR/good.env" "0123456789abcdef0123456789abcdef01234567"
resolved="$("$RESOLVER" --pin-file "$TMP_DIR/good.env" --print-ref)" \
  || fail "$RESOLVER rejected a valid 40-character SHA"
[ "$resolved" = "0123456789abcdef0123456789abcdef01234567" ] \
  || fail "$RESOLVER printed '$resolved' for a valid pin"

# Characterization of the repository's *current* state: with the pin empty, the
# resolver fails here too. This test passes by asserting that failure — the CI
# image gate is the thing that must stay red, and it does so through this exact
# exit status.
if [ -z "$pinned_ref" ]; then
  if "$RESOLVER" --print-ref >/dev/null 2>&1; then
    fail "$PIN_FILE has no commit, yet $RESOLVER --print-ref succeeded"
  fi
  message="$("$RESOLVER" --print-ref 2>&1 >/dev/null || true)"
  case "$message" in
    *STREAMLINE_CORE_REF*) ;;
    *) fail "the unpinned failure must name STREAMLINE_CORE_REF, got: $message" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 3. The CI image gate reaches the failing resolver, unconditionally
# ---------------------------------------------------------------------------
image_job="$(job_block "$CI" image-build)"
[ -n "$image_job" ] || fail "$CI must define an image-build job"

if [ -n "$image_job" ]; then
  printf '%s\n' "$image_job" | grep -Fq -- "$RESOLVER --print-ref" \
    || fail "$CI image-build must resolve the pin with '$RESOLVER --print-ref'"

  # The resolver's failure must reach the job: no output/exit-status swallowing.
  while IFS= read -r line; do
    case "$line" in
      *"$RESOLVER"*)
        case "$line" in
          *"2>/dev/null"*|*"|| true"*|*"|| echo"*|*"if ref="*)
            fail "$CI swallows the resolver's failure: $line" ;;
        esac ;;
    esac
  done <<EOF
$image_job
EOF

  # A conditional step is how the skip came back last time.
  if printf '%s\n' "$image_job" | grep -Eq '^[[:space:]]+if:'; then
    fail "$CI image-build must not guard any step with 'if:' — the gate has to run and fail while the pin is empty"
  fi
  if printf '%s\n' "$image_job" | grep -Fq 'continue-on-error'; then
    fail "$CI image-build must not use continue-on-error"
  fi
  for forbidden in 'pinned=false' 'pinned=true' '::notice::' 'gate skipped' 'skipping'; do
    if printf '%s\n' "$image_job" | grep -Fq "$forbidden"; then
      fail "$CI image-build must not report a skipped/notice outcome (found: $forbidden)"
    fi
  done
  printf '%s\n' "$image_job" | grep -Fq 'set -euo pipefail' \
    || fail "$CI image-build must run the resolver under 'set -euo pipefail'"

  # The gate is only a gate if it actually builds and smoke-tests.
  printf '%s\n' "$image_job" | grep -Fq 'docker/build-push-action' \
    || fail "$CI image-build must build the image"
  printf '%s\n' "$image_job" | grep -Fq 'docker-compose.test.yml' \
    || fail "$CI image-build must smoke-test the built image"
  printf '%s\n' "$image_job" | grep -Fq 'push: false' \
    || fail "$CI image-build must not push (docker-publish.yml is the only publisher)"
fi

# ---------------------------------------------------------------------------
# 4. The release publisher resolves the same pin, equally unforgiving
# ---------------------------------------------------------------------------
publish_job="$(job_block "$PUBLISHER" release-contract)"
[ -n "$publish_job" ] || fail "$PUBLISHER must define a release-contract job"

if [ -n "$publish_job" ]; then
  printf '%s\n' "$publish_job" | grep -Fq -- "$RESOLVER --print-ref" \
    || fail "$PUBLISHER must resolve the release pin with '$RESOLVER --print-ref'"
  while IFS= read -r line; do
    case "$line" in
      *"$RESOLVER"*)
        case "$line" in
          *"2>/dev/null"*|*"|| true"*) fail "$PUBLISHER swallows the resolver's failure: $line" ;;
        esac ;;
    esac
  done <<EOF
$publish_job
EOF
fi

if grep -Fq 'continue-on-error' "$PUBLISHER"; then
  fail "$PUBLISHER must not use continue-on-error: a release gate cannot be advisory"
fi

if [ "$status" -eq 0 ]; then
  if [ -z "$pinned_ref" ]; then
    echo "core-pin gate passed: pin is empty and the image gate fails closed (CI image-build stays red until a SHA is pinned)"
  else
    echo "core-pin gate passed: pin is an immutable SHA and the image gate runs unconditionally"
  fi
fi

exit "$status"
