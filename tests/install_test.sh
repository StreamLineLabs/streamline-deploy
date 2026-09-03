#!/usr/bin/env bash
# Characterization tests for scripts/install.sh.
#
# The installer is sourced as a library (STREAMLINE_INSTALLER_LIB=1) so the
# pure helpers can be exercised without any network access or installation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# shellcheck disable=SC1090  # path is computed
STREAMLINE_INSTALLER_LIB=1 . "$INSTALLER"

# --- Platform detection ------------------------------------------------------
OS=""; PLATFORM=""
detect_platform_from "Linux" "x86_64"
[ "$PLATFORM" = "linux-x86_64" ] || fail "linux/x86_64 mapped to '$PLATFORM'"
detect_platform_from "Darwin" "arm64"
[ "$PLATFORM" = "darwin-aarch64" ] || fail "darwin/arm64 mapped to '$PLATFORM'"
[ "$ARCH_ALTERNATIVES" = "aarch64 arm64" ] || fail "unexpected arch alternatives '$ARCH_ALTERNATIVES'"

if ( detect_platform_from "Linux" "sparc64" ) 2>/dev/null; then
  fail "unsupported architecture should be rejected"
fi

# --- Asset selection ---------------------------------------------------------
ASSETS="$TMP_DIR/assets.txt"
cat > "$ASSETS" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
streamline-0.3.0-aarch64-apple-darwin.tar.gz
streamline-0.3.0-x86_64-pc-windows-msvc.zip
SHA256SUMS
SHA256SUMS.sig
EOF

detect_platform_from "Linux" "x86_64"
selected="$(select_asset "$OS" "$ARCH_ALTERNATIVES" < "$ASSETS")"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" ] \
  || fail "linux asset resolved to '$selected'"

detect_platform_from "Darwin" "arm64"
selected="$(select_asset "$OS" "$ARCH_ALTERNATIVES" < "$ASSETS")"
[ "$selected" = "streamline-0.3.0-aarch64-apple-darwin.tar.gz" ] \
  || fail "darwin asset resolved to '$selected'"

# Signature and checksum files are never installable artifacts.
if ( select_asset "linux" "x86_64" < <(printf 'SHA256SUMS\nSHA256SUMS.sig\n') ) >/dev/null 2>&1; then
  fail "checksum/signature files must not be selected as release archives"
fi

# glibc/musl is not real ambiguity: it resolves the same way on every run.
cat > "$TMP_DIR/libc.txt" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz
EOF
selected="$(select_asset "linux" "x86_64" gnu < "$TMP_DIR/libc.txt")"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" ] \
  || fail "gnu/musl pair resolved to '$selected' instead of the gnu build"

# The default preference is gnu, so the same list resolves identically without
# an explicit libc argument.
selected="$(select_asset "linux" "x86_64" < "$TMP_DIR/libc.txt")"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" ] \
  || fail "default libc preference resolved to '$selected' instead of the gnu build"

# musl remains selectable.
selected="$(select_asset "linux" "x86_64" musl < "$TMP_DIR/libc.txt")"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz" ] \
  || fail "musl preference resolved to '$selected'"

# The libc preference is reachable from the command line and the environment.
grep -Fq -- '--libc)' "$INSTALLER" \
  || fail "installer must expose a --libc flag to override the libc preference"
grep -Fq 'STREAMLINE_LIBC' "$INSTALLER" \
  || fail "installer must honour STREAMLINE_LIBC"

# --- Requested libc is a filter, not a preference ---------------------------
# A release that publishes only the *other* flavour must fail explicitly. The
# selector used to resolve uniqueness first and only then look at the libc, so
# a musl-only release satisfied `--libc gnu` — one candidate, therefore
# "unambiguous" — and installed binaries that cannot start on a glibc host.
cat > "$TMP_DIR/musl-only.txt" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz
SHA256SUMS
EOF
if selected="$( select_asset "linux" "x86_64" gnu < "$TMP_DIR/musl-only.txt" 2>/dev/null )"; then
  fail "a musl-only release must not satisfy --libc gnu (selected '$selected')"
fi
# ... and the message has to say what it found, so the user can choose.
err="$( select_asset "linux" "x86_64" gnu < "$TMP_DIR/musl-only.txt" 2>&1 >/dev/null || true )"
case "$err" in
  *"no gnu archive"*) ;;
  *) fail "the opposite-flavour failure must name the requested flavour, got: $err" ;;
esac
case "$err" in
  *musl*) ;;
  *) fail "the opposite-flavour failure must list the archives the release does publish, got: $err" ;;
esac

cat > "$TMP_DIR/gnu-only.txt" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
SHA256SUMS
EOF
if selected="$( select_asset "linux" "x86_64" musl < "$TMP_DIR/gnu-only.txt" 2>/dev/null )"; then
  fail "a glibc-only release must not satisfy --libc musl (selected '$selected')"
fi

# A release that does not distinguish flavours has nothing to filter on, so a
# single unqualified archive still resolves.
cat > "$TMP_DIR/unflavoured.txt" <<'EOF'
streamline-0.3.0-linux-x86_64.tar.gz
SHA256SUMS
EOF
selected="$(select_asset "linux" "x86_64" gnu < "$TMP_DIR/unflavoured.txt")"
[ "$selected" = "streamline-0.3.0-linux-x86_64.tar.gz" ] \
  || fail "an unflavoured linux archive resolved to '$selected'"

# --- End-to-end resolution from hermetic release metadata -------------------
# The same JSON shape the GitHub releases API returns, parsed by the installer's
# own helpers. No network: the fixture is the response.
release_metadata() {
  # release_metadata <asset names...>
  printf '{\n  "tag_name": "v0.3.0",\n  "assets": [\n'
  _first=1
  for _asset in "$@"; do
    [ "$_first" -eq 1 ] || printf ',\n'
    _first=0
    printf '    {"name": "%s", "size": 1024}' "$_asset"
  done
  printf '\n  ]\n}\n'
}

BOTH_FLAVOURS="$(release_metadata \
  streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz \
  streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz \
  SHA256SUMS SHA256SUMS.sig)"

version="$(printf '%s' "$BOTH_FLAVOURS" | parse_tag_name)"
[ "$version" = "0.3.0" ] || fail "release metadata resolved version '$version'"

assets="$(printf '%s' "$BOTH_FLAVOURS" | parse_asset_names)"
selected="$(printf '%s\n' "$assets" | select_asset "linux" "x86_64" gnu)"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" ] \
  || fail "gnu request against a two-flavour release resolved to '$selected'"
selected="$(printf '%s\n' "$assets" | select_asset "linux" "x86_64" musl)"
[ "$selected" = "streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz" ] \
  || fail "musl request against a two-flavour release resolved to '$selected'"

# Checksum verification stays mandatory on that path: the selected archive must
# still resolve a checksum asset, and the digest is still compared.
picked="$(printf '%s\n' "$assets" | select_checksum_asset "$selected")"
[ "$picked" = "SHA256SUMS" ] \
  || fail "checksum asset for the musl archive resolved to '$picked'"

MUSL_ONLY="$(release_metadata \
  streamline-0.3.0-x86_64-unknown-linux-musl.tar.gz \
  SHA256SUMS)"
assets="$(printf '%s' "$MUSL_ONLY" | parse_asset_names)"
if selected="$( printf '%s\n' "$assets" | select_asset "linux" "x86_64" gnu 2>/dev/null )"; then
  fail "musl-only release metadata must not satisfy a gnu request (selected '$selected')"
fi

# Signature and checksum assets are never installable, in either fixture.
for name in SHA256SUMS SHA256SUMS.sig; do
  is_metadata_asset "$name" \
    || fail "$name must be treated as release metadata, not an installable archive"
done

# Genuine ambiguity (two archives of the requested flavour) still fails closed.
cat > "$TMP_DIR/ambiguous.txt" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
streamline-server-0.3.0-x86_64-unknown-linux-gnu.tar.gz
EOF
if ( select_asset "linux" "x86_64" gnu < "$TMP_DIR/ambiguous.txt" ) >/dev/null 2>&1; then
  fail "ambiguous asset matches must fail closed"
fi

# An unknown libc flavour cannot silently fall back to an arbitrary archive.
if ( select_asset "linux" "x86_64" uclibc < "$TMP_DIR/libc.txt" ) >/dev/null 2>&1; then
  fail "an unmatched libc preference must not resolve ambiguity by guessing"
fi

# --- Checksum file selection -------------------------------------------------
picked="$(select_checksum_asset "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" < "$ASSETS")"
[ "$picked" = "SHA256SUMS" ] || fail "checksum asset resolved to '$picked'"

cat > "$TMP_DIR/per-asset.txt" <<'EOF'
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz.sha256
EOF
picked="$(select_checksum_asset "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" < "$TMP_DIR/per-asset.txt")"
[ "$picked" = "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz.sha256" ] \
  || fail "per-asset checksum resolved to '$picked'"

if ( select_checksum_asset "streamline.tar.gz" < <(printf 'streamline.tar.gz\n') ) >/dev/null 2>&1; then
  fail "a release without checksums must fail closed"
fi

# --- Checksum extraction and verification -----------------------------------
ARCHIVE="$TMP_DIR/streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz"
printf 'payload' > "$ARCHIVE"
EXPECTED="$(sha256_of "$ARCHIVE")"
[ -n "$EXPECTED" ] || fail "sha256_of produced no digest"

cat > "$TMP_DIR/SHA256SUMS" <<EOF
0000000000000000000000000000000000000000000000000000000000000000  other-file.tar.gz
$EXPECTED  streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz
EOF

extracted="$(checksum_for_asset "$TMP_DIR/SHA256SUMS" "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz")"
[ "$extracted" = "$EXPECTED" ] || fail "checksum extraction returned '$extracted'"

# BSD-style '*name' entries are also understood.
printf '%s *%s\n' "$EXPECTED" "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz" > "$TMP_DIR/BSDSUMS"
extracted="$(checksum_for_asset "$TMP_DIR/BSDSUMS" "streamline-0.3.0-x86_64-unknown-linux-gnu.tar.gz")"
[ "$extracted" = "$EXPECTED" ] || fail "BSD-style checksum extraction returned '$extracted'"

if ( checksum_for_asset "$TMP_DIR/SHA256SUMS" "missing.tar.gz" ) >/dev/null 2>&1; then
  fail "a missing checksum entry must fail closed"
fi

verify_checksum "$ARCHIVE" "$EXPECTED" >/dev/null \
  || fail "verification of a matching digest failed"

if ( verify_checksum "$ARCHIVE" "0000000000000000000000000000000000000000000000000000000000000000" ) >/dev/null 2>&1; then
  fail "verification must reject a mismatching digest"
fi

# --- No stale version fallback ----------------------------------------------
if grep -Eq 'VERSION="0\.2\.0"' "$INSTALLER"; then
  fail "installer must not fall back to a hard-coded 0.2.0"
fi
grep -Fq 'Could not determine the latest release' "$INSTALLER" \
  || fail "installer must fail closed when the version cannot be resolved"

# --- Checksum verification is not optional ----------------------------------
grep -Fq 'no checksum file' "$INSTALLER" \
  || fail "installer must refuse releases that publish no checksums"
if grep -Eq '\-\-(skip|no)-(checksum|verify)' "$INSTALLER"; then
  fail "installer must not offer a checksum bypass flag"
fi

echo "install.sh characterization passed"
