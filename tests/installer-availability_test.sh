#!/usr/bin/env bash
# Static/behavioral gate for the intentionally unavailable prebuilt installer.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

endpoint="$(printf '%s%s%s' 'get.streamline' '.' 'dev')"

joined_shell_lines() {
  # Join ordinary shell continuations so a copy-paste command cannot evade the
  # scan by putting "| sh" on the next line.
  awk '
    {
      line = $0
      if (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, "", line)
        printf "%s ", line
        next
      }
      if (line ~ /\|[[:space:]]*$/) {
        printf "%s ", line
        next
      }
      print line
    }
  ' "$1"
}

# Do not publish copy-paste installation commands before the endpoint and
# signed release assets are controlled and available.
while IFS= read -r file; do
  case "$file" in
    CHANGELOG.md|tests/*) continue ;;
  esac
  [ -f "$REPO_ROOT/$file" ] || continue
  grep -Fq "$endpoint" "$REPO_ROOT/$file" \
    && fail "$file advertises the unavailable installer endpoint"
  joined_shell_lines "$REPO_ROOT/$file" \
    | grep -Eq '(curl|wget)[^|]*(\|[[:space:]]*(sh|bash))' \
    && fail "$file advertises a pipe-to-shell installer command"
  grep -Eq 'releases/download/v0\.4\.0|streamline(-server|-cli)?-0\.4\.0-[^[:space:]`"]+\.(tar\.gz|tgz|zip)|--version[[:space:]]+0\.4\.0' "$REPO_ROOT/$file" \
    && fail "$file advertises a prebuilt 0.4.0 artifact that has not been verified to exist"
done < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard \
  '*.md' '*.sh' '*.yml' '*.yaml' '*.txt')

grep -Fq 'INSTALLER_RELEASES_AVAILABLE=0' "$INSTALLER" \
  || fail "installer must keep an explicit unavailable release gate"
grep -Fq 'readonly INSTALLER_RELEASES_AVAILABLE' "$INSTALLER" \
  || fail "the unavailable release gate must not be overridable from the environment"
# shellcheck disable=SC2016  # match the literal shell guard, not this process
grep -Fq 'if [ "$INSTALLER_RELEASES_AVAILABLE" -ne 1 ]' "$INSTALLER" \
  || fail "installer entry point must enforce the unavailable release gate"
grep -Fq 'git clone https://github.com/streamlinelabs/streamline.git' "$INSTALLER" \
  || fail "installer help must direct users to the public source repository"
grep -Fq 'cargo build --release' "$INSTALLER" \
  || fail "installer help must provide a source-build command"
grep -Eq '0\.3\.0' "$INSTALLER" \
  && fail "installer must not advertise an unavailable release version"

# Help is the only successful entry point while releases are unavailable. It
# may explain how to build from source, but it must not hand out the endpoint,
# a pipe-to-shell command, or a speculative binary version.
help_output="$("$INSTALLER" --help 2>&1)" \
  || fail "installer --help must remain available while installation is disabled"
printf '%s\n' "$help_output" | grep -Fq "$endpoint" \
  && fail "installer --help advertises the unavailable endpoint"
printf '%s\n' "$help_output" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sh|bash)' \
  && fail "installer --help advertises pipe-to-shell"
printf '%s\n' "$help_output" | grep -Eq '0\.3\.0|releases/download/' \
  && fail "installer --help advertises an unverified release artifact"

# An environment variable with the same name must not turn dormant download
# code on. PATH is deliberately empty here: if the source constant regresses to
# an environment-controlled default, the script still cannot reach curl/wget.
set +e
override_output="$(PATH=/nonexistent INSTALLER_RELEASES_AVAILABLE=1 "$INSTALLER" 2>&1)"
override_status=$?
set -e
[ "$override_status" -ne 0 ] \
  || fail "INSTALLER_RELEASES_AVAILABLE=1 enabled prebuilt installation"
case "$override_output" in
  *"Prebuilt Streamline installation is unavailable"*) ;;
  *) fail "environment override bypassed the fail-closed diagnostic: $override_output" ;;
esac

# Exercise the entry point without permitting a regression to touch the
# network. The unavailable diagnostic, not a mocked download failure, must win.
# shellcheck disable=SC1090
STREAMLINE_INSTALLER_LIB=1 . "$INSTALLER"
http_get() {
  fail "installer attempted a network request while unavailable"
}
http_download() {
  fail "installer attempted a download while unavailable"
}

set +e
output="$(main 2>&1)"
status=$?
set -e

[ "$status" -ne 0 ] || fail "installer entry point succeeded while unavailable"
case "$output" in
  *"Prebuilt Streamline installation is unavailable"*) ;;
  *) fail "installer failure did not explain its unavailable state: $output" ;;
esac

echo "installer availability gate passed"
