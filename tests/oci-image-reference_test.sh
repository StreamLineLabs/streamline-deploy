#!/usr/bin/env bash
# Regression tests for the OCI reference parser used by feature-image gates.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/oci-image-reference-lib.sh
source "$REPO_ROOT/tests/oci-image-reference-lib.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_parse() {
  local reference="$1"
  local expected_key="$2"

  oci_parse_image_reference "$reference" \
    || fail "valid reference was rejected: $reference ($OCI_IMAGE_PARSE_ERROR)"
  [ "$OCI_IMAGE_REFERENCE" = "$reference" ] \
    || fail "parser rewrote the emitted reference '$reference' as '$OCI_IMAGE_REFERENCE'"
  [ "$OCI_IMAGE_COMPARISON_KEY" = "$expected_key" ] \
    || fail "expected comparison key '$expected_key' for '$reference', got '$OCI_IMAGE_COMPARISON_KEY'"
}

assert_invalid_port() {
  local reference="$1"
  local parse_status
  local policy_status

  if oci_parse_image_reference "$reference"; then
    fail "invalid explicit registry port was accepted: $reference"
  else
    parse_status=$?
  fi
  [ "$parse_status" -eq 2 ] \
    || fail "invalid reference returned status $parse_status instead of 2: $reference"
  [ "$OCI_IMAGE_REFERENCE" = "$reference" ] \
    || fail "invalid reference spelling was not preserved: $reference"
  [ -z "$OCI_IMAGE_COMPARISON_KEY" ] \
    || fail "invalid reference retained comparison key '$OCI_IMAGE_COMPARISON_KEY': $reference"
  [ -n "$OCI_IMAGE_PARSE_ERROR" ] \
    || fail "invalid reference did not explain its parse failure: $reference"

  if oci_is_generic_streamline_core_image "$reference"; then
    fail "invalid reference was treated as an allowed generic comparison: $reference"
  else
    policy_status=$?
  fi
  [ "$policy_status" -eq 2 ] \
    || fail "policy helper did not fail closed for invalid reference: $reference"
}

# Comparisons canonicalize the numeric identity of an explicit registry port,
# but diagnostics and re-emission retain the exact supplied spelling.
assert_parse \
  'localhost:05000/team/streamline-moonshot:dev@sha256:fixture' \
  'localhost:5000/team/streamline-moonshot'
assert_parse \
  'registry.example:0443/team/streamline:release@sha256:fixture' \
  'registry.example:443/team/streamline'
assert_parse \
  'registry.example:00080/team/streamline-moonshot' \
  'registry.example:80/team/streamline-moonshot'
assert_parse \
  'registry.example:1/team/streamline' \
  'registry.example:1/team/streamline'
assert_parse \
  'registry.example:65535/team/streamline' \
  'registry.example:65535/team/streamline'
assert_parse \
  '[2001:db8::1]:0443/team/streamline:release@sha256:fixture' \
  '[2001:db8::1]:443/team/streamline'

oci_parse_image_reference 'registry.example:443/team/streamline'
port_443_key="$OCI_IMAGE_COMPARISON_KEY"
oci_parse_image_reference 'registry.example:0443/team/streamline'
[ "$OCI_IMAGE_COMPARISON_KEY" = "$port_443_key" ] \
  || fail "ports 443 and 0443 did not compare as the same repository"

oci_parse_image_reference 'registry.example:80/team/streamline'
port_80_key="$OCI_IMAGE_COMPARISON_KEY"
oci_parse_image_reference 'registry.example:00080/team/streamline'
[ "$OCI_IMAGE_COMPARISON_KEY" = "$port_80_key" ] \
  || fail "ports 80 and 00080 did not compare as the same repository"

for reference in \
  'registry.example:0/team/streamline' \
  'registry.example:0000/team/streamline' \
  'registry.example:65536/team/streamline' \
  'registry.example:999999999999999999999999999999999999/team/streamline' \
  'registry.example:/team/streamline' \
  'registry.example:+80/team/streamline' \
  'registry.example:80x/team/streamline' \
  '[2001:db8::1]:/team/streamline'; do
  assert_invalid_port "$reference"
done

# A tag, a digest, or both are aliases of the same generic core repository.
# Feature-gated demos must not accept one merely because punctuation obscures
# the final repository component.
generic_aliases=(
  'streamline'
  'streamline:dev'
  'streamline@sha256:fixture'
  'streamline:dev@sha256:fixture'
  'ghcr.io/streamlinelabs/streamline:release@sha256:fixture'
  'localhost:05000/team/streamline:custom@sha256:fixture'
  '[2001:db8::1]:0443/team/streamline:custom@sha256:fixture'
)

for reference in "${generic_aliases[@]}"; do
  oci_is_generic_streamline_core_image "$reference" \
    || fail "generic core image alias was accepted: $reference"
done

for reference in \
  'streamline-moonshot:dev' \
  'localhost:5000/team/streamline-moonshot:dev@sha256:fixture'; do
  if oci_is_generic_streamline_core_image "$reference"; then
    fail "feature-specific image was mistaken for generic core: $reference"
  fi
done

echo "OCI image-reference regression passed: ports bounded and normalized, original references preserved"
