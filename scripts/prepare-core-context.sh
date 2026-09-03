#!/usr/bin/env bash
# Materialise the Streamline core sources that the official image builds from.
#
# streamline-deploy ships deployment artifacts, not the Streamline core source
# tree. `Dockerfile` compiles the core crates, so its build context must be a
# checkout of the core repository at an immutable commit. This script produces
# that context from the pin recorded in core-source.env.
#
# The prepared context is core sources *plus* a small overlay: the deployment
# assets that the images bake in (currently the edge appliance config) live in
# this repository, never in core, so a context that carried only the core
# checkout could not build Dockerfile.edge. The overlay is copied to a
# namespaced `.deploy/` directory so it can never shadow a core path.
#
# Usage:
#   scripts/prepare-core-context.sh [options]
#
# Options:
#   --dest DIR       Destination directory for the checkout (default: .build/core)
#   --repo URL       Override the core repository URL
#   --ref SHA        Override the pinned commit SHA (full 40-character SHA)
#   --pin-file FILE  Pin file to read (default: <repo root>/core-source.env)
#   --check-only     Validate the pin and exit without any network access
#   --print-ref      Print the validated commit SHA only, then exit
#   --help           Show this help
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="$REPO_ROOT/core-source.env"
DEST="${STREAMLINE_CORE_CONTEXT:-$REPO_ROOT/.build/core}"
REPO_OVERRIDE=""
REF_OVERRIDE=""
CHECK_ONLY=0
PRINT_REF=0

usage() {
  # Print the contiguous header comment block. Deriving the range keeps --help
  # in sync with the documentation above; the previous hard-coded line range
  # silently truncated the option list whenever the header grew.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)      DEST="${2:?--dest requires a directory}"; shift 2 ;;
    --repo)      REPO_OVERRIDE="${2:?--repo requires a URL}"; shift 2 ;;
    --ref)       REF_OVERRIDE="${2:?--ref requires a commit SHA}"; shift 2 ;;
    --pin-file)  PIN_FILE="${2:?--pin-file requires a path}"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --print-ref) PRINT_REF=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    *)           die "Unknown option: $1" ;;
  esac
done

[ -f "$PIN_FILE" ] || die "pin file not found: $PIN_FILE"

STREAMLINE_CORE_REPO=""
STREAMLINE_CORE_REF=""
# shellcheck disable=SC1090  # pin file path is a caller-supplied variable
. "$PIN_FILE"

[ -n "$REPO_OVERRIDE" ] && STREAMLINE_CORE_REPO="$REPO_OVERRIDE"
[ -n "$REF_OVERRIDE" ] && STREAMLINE_CORE_REF="$REF_OVERRIDE"

if [ -z "$STREAMLINE_CORE_REPO" ]; then
  die "STREAMLINE_CORE_REPO is not set in $PIN_FILE (and --repo was not given)"
fi

if [ -z "$STREAMLINE_CORE_REF" ]; then
  die "STREAMLINE_CORE_REF is not set in $PIN_FILE (and --ref was not given).
       Pin the full 40-character core commit SHA that this image release builds from.
       Image builds fail closed rather than build an unidentified branch tip."
fi

if ! printf '%s' "$STREAMLINE_CORE_REF" | grep -Eq '^[0-9a-f]{40}$'; then
  die "STREAMLINE_CORE_REF='$STREAMLINE_CORE_REF' is not an immutable commit SHA.
       Branches and tags are mutable and are rejected; use the full 40-character SHA."
fi

if [ "$PRINT_REF" -eq 1 ]; then
  printf '%s\n' "$STREAMLINE_CORE_REF"
  exit 0
fi

echo "core repository: $STREAMLINE_CORE_REPO"
echo "core commit:     $STREAMLINE_CORE_REF"
echo "context dir:     $DEST"

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "check-only: pin is valid; no checkout performed"
  exit 0
fi

command -v git >/dev/null 2>&1 || die "git is required to prepare the core build context"

rm -rf "$DEST"
mkdir -p "$DEST"

# Fetch exactly the pinned commit; never a branch tip.
git -C "$DEST" init --quiet
git -C "$DEST" remote add origin "$STREAMLINE_CORE_REPO"
git -C "$DEST" fetch --quiet --depth 1 origin "$STREAMLINE_CORE_REF"
git -C "$DEST" checkout --quiet FETCH_HEAD

ACTUAL="$(git -C "$DEST" rev-parse HEAD)"
if [ "$ACTUAL" != "$STREAMLINE_CORE_REF" ]; then
  die "checkout resolved to $ACTUAL but $STREAMLINE_CORE_REF was pinned"
fi

# Drop VCS metadata so the build context is a pure source snapshot.
rm -rf "$DEST/.git"

# Overlay this repository's image assets. Dockerfile.edge bakes in
# docker/edge/streamline-edge.toml, which exists here and not in core, so the
# context has to carry both trees. `.deploy/` is namespaced precisely so the
# overlay can never overwrite a core path; if core ever grows one, fail rather
# than silently merge two unrelated directories.
OVERLAY_DEST="$DEST/.deploy"
if [ -e "$OVERLAY_DEST" ]; then
  die "core commit $ACTUAL already contains .deploy/; the deployment overlay would overwrite it"
fi
mkdir -p "$OVERLAY_DEST"
cp -R "$REPO_ROOT/docker" "$OVERLAY_DEST/docker"

echo "core sources prepared at $DEST (commit $ACTUAL)"
echo "deployment overlay copied to $OVERLAY_DEST/docker"
