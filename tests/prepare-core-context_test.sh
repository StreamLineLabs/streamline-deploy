#!/usr/bin/env bash
# Characterization tests for scripts/prepare-core-context.sh.
#
# Every case below runs with --check-only so the suite never touches the
# network: only argument handling and pin validation are exercised.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/prepare-core-context.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VALID_SHA="0123456789abcdef0123456789abcdef01234567"

write_pin() {
  # write_pin <file> <ref>
  cat > "$1" <<EOF
STREAMLINE_CORE_REPO=https://github.com/streamlinelabs/streamline.git
STREAMLINE_CORE_REF=$2
EOF
}

expect_failure() {
  # expect_failure <expected-substring> <args...>
  local expected="$1"
  shift
  local output status=0
  output="$("$SCRIPT" "$@" 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    echo "FAIL: expected non-zero exit for: $*" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" <<<"$output"; then
    echo "FAIL: expected '$expected' in output of: $*" >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_success() {
  # expect_success <expected-substring> <args...>
  local expected="$1"
  shift
  local output
  output="$("$SCRIPT" "$@" 2>&1)"
  if ! grep -Fq "$expected" <<<"$output"; then
    echo "FAIL: expected '$expected' in output of: $*" >&2
    echo "$output" >&2
    exit 1
  fi
}

# --- Unset pin fails closed -------------------------------------------------
write_pin "$TMP_DIR/unset.env" ""
expect_failure "STREAMLINE_CORE_REF is not set" \
  --pin-file "$TMP_DIR/unset.env" --check-only

# --- Mutable refs are rejected ---------------------------------------------
write_pin "$TMP_DIR/tag.env" "v0.3.0"
expect_failure "not an immutable commit SHA" \
  --pin-file "$TMP_DIR/tag.env" --check-only

write_pin "$TMP_DIR/branch.env" "main"
expect_failure "not an immutable commit SHA" \
  --pin-file "$TMP_DIR/branch.env" --check-only

write_pin "$TMP_DIR/short.env" "0123456"
expect_failure "not an immutable commit SHA" \
  --pin-file "$TMP_DIR/short.env" --check-only

# --- Full commit SHA is accepted -------------------------------------------
write_pin "$TMP_DIR/valid.env" "$VALID_SHA"
expect_success "$VALID_SHA" --pin-file "$TMP_DIR/valid.env" --check-only

# --- Command-line ref overrides the pin file -------------------------------
OVERRIDE_SHA="89abcdef0123456789abcdef0123456789abcdef"
expect_success "$OVERRIDE_SHA" \
  --pin-file "$TMP_DIR/unset.env" --ref "$OVERRIDE_SHA" --check-only

# --- --print-ref emits the validated SHA and nothing else -------------------
PRINTED="$("$SCRIPT" --pin-file "$TMP_DIR/valid.env" --print-ref)"
test "$PRINTED" = "$VALID_SHA" || {
  echo "FAIL: --print-ref emitted '$PRINTED', expected '$VALID_SHA'" >&2
  exit 1
}
expect_failure "not an immutable commit SHA" \
  --pin-file "$TMP_DIR/tag.env" --print-ref

# --- Missing pin file fails closed -----------------------------------------
expect_failure "pin file not found" \
  --pin-file "$TMP_DIR/does-not-exist.env" --check-only

# --- Unknown options fail closed -------------------------------------------
expect_failure "Unknown option" --check-only --bogus

# --- Repository URL must be present ----------------------------------------
printf 'STREAMLINE_CORE_REF=%s\n' "$VALID_SHA" > "$TMP_DIR/norepo.env"
expect_failure "STREAMLINE_CORE_REPO is not set" \
  --pin-file "$TMP_DIR/norepo.env" --check-only

# --- The checked-in pin file is syntactically valid -------------------------
if ! grep -Eq '^STREAMLINE_CORE_REPO=.+$' "$REPO_ROOT/core-source.env"; then
  echo "FAIL: core-source.env must declare STREAMLINE_CORE_REPO" >&2
  exit 1
fi
if ! grep -Eq '^STREAMLINE_CORE_REF=' "$REPO_ROOT/core-source.env"; then
  echo "FAIL: core-source.env must declare STREAMLINE_CORE_REF" >&2
  exit 1
fi

echo "prepare-core-context characterization passed"
