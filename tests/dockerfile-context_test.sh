#!/usr/bin/env bash
# Static gate: the official image must be built from the pinned Streamline core
# sources, never from this repository's working tree.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- The Dockerfile documents and enforces the prepared build context -------
grep -Fq 'core-source.env' Dockerfile \
  || fail "Dockerfile must document the pinned core source (core-source.env)"
grep -Fq 'scripts/prepare-core-context.sh' Dockerfile \
  || fail "Dockerfile must reference scripts/prepare-core-context.sh"
grep -Eq '^ARG STREAMLINE_EDITION' Dockerfile \
  || fail "Dockerfile must declare ARG STREAMLINE_EDITION"
grep -Eq '^ARG STREAMLINE_FEATURES' Dockerfile \
  || fail "Dockerfile must declare ARG STREAMLINE_FEATURES"
grep -Fq 'Unsupported STREAMLINE_EDITION' Dockerfile \
  || fail "Dockerfile must fail closed on an unknown edition"
grep -Fq 'dev.streamline.edition' Dockerfile \
  || fail "Dockerfile must label the image edition so charts can check capabilities"

# The old per-crate COPY list silently broke whenever core changed layout.
if grep -Eq '^COPY crates/' Dockerfile; then
  fail "Dockerfile must not hard-code core crate paths"
fi

# --- Every core-compiling Dockerfile needs the prepared context -------------
# Dockerfile.edge drifted for exactly this reason: it kept a per-crate COPY list
# pointing at paths this repository has never contained, so the gate covers any
# Dockerfile that runs cargo, not just the official one.
CORE_DOCKERFILES=()
while IFS= read -r df; do
  grep -Fq 'cargo build' "$df" && CORE_DOCKERFILES+=("$df")
done < <(find . -maxdepth 2 -name 'Dockerfile*' -not -path './.build/*' | sort)

[ "${#CORE_DOCKERFILES[@]}" -ge 3 ] \
  || fail "expected Dockerfile, Dockerfile.edge and playground/Dockerfile to compile core, found: ${CORE_DOCKERFILES[*]:-none}"

for df in "${CORE_DOCKERFILES[@]}"; do
  grep -Fq 'prepare-core-context.sh' "$df" \
    || fail "$df compiles core but does not document scripts/prepare-core-context.sh"
  grep -Eq '^COPY \. \.$' "$df" \
    || fail "$df must copy the whole prepared context, not a hand-maintained path list"
  grep -Fq 'Cargo.lock missing from the build context' "$df" \
    || fail "$df must fail closed when the context is not a core checkout"
  grep -Eq 'cargo build .*--locked' "$df" \
    || fail "$df must build with --locked so the image matches the pinned commit"
  # The per-crate COPY lists silently broke whenever core changed layout.
  if grep -Eq '^COPY (crates/|src/|Cargo\.toml)' "$df"; then
    fail "$df must not hard-code core source paths"
  fi

  builder_stage="$(awk '
    /^FROM .* AS builder/ { in_builder = 1 }
    in_builder && /^FROM / && $0 !~ / AS builder/ { exit }
    in_builder { print }
  ' "$df")"
  runtime_stage="$(awk '
    /^FROM / { stages += 1 }
    stages >= 2 { print }
  ' "$df")"
  builder_code="$(printf '%s\n' "$builder_stage" | sed '/^[[:space:]]*#/d')"

  # Bundled DuckDB/libduckdb-sys is C++. Any image that builds `full`, explicit
  # `analytics`, or an arbitrary STREAMLINE_FEATURES list must provide a C++
  # compiler in the builder only.
  if printf '%s\n' "$builder_code" \
      | grep -Eq 'STREAMLINE_FEATURES|--features[^[:cntrl:]]*(full|analytics)'; then
    printf '%s\n' "$builder_stage" | grep -Eq '^[[:space:]]+g\+\+[[:space:]]*\\?$' \
      || fail "$df builder must install g++ for full/analytics DuckDB builds"
    printf '%s\n' "$builder_stage" | grep -Fq -- '--no-install-recommends' \
      || fail "$df builder dependencies must stay non-recommended"
  fi

  if printf '%s\n' "$runtime_stage" \
      | grep -Eq '^[[:space:]]+(g\+\+|build-essential)[[:space:]]*\\?$'; then
    fail "$df must keep C++ build tooling out of the runtime image"
  fi
done

# --- No Compose file may build a core-compiling Dockerfile from this repo ----
for compose in docker-compose*.yml */docker-compose*.yml; do
  [ -f "$compose" ] || continue
  for df in "${CORE_DOCKERFILES[@]}"; do
    base="${df#./}"
    if grep -Eq "dockerfile: ${base}[[:space:]]*\$" "$compose" \
      && grep -Eq 'context: \.[[:space:]]*$' "$compose"; then
      fail "$compose builds $base from this repo, which has no core sources"
    fi
  done
done

# --- No document may tell users to build core from this repository ----------
# `docker build -t … .` with this repository as the context cannot work: there
# are no Rust sources here, so it fails with "Cargo.toml not found" after the
# reader has followed the instruction. k8s/README.md shipped exactly that.
# Every documented build must prepare the pinned core context first and build
# against it.
CORE_DOCKERFILE_NAMES=()
for df in "${CORE_DOCKERFILES[@]}"; do
  CORE_DOCKERFILE_NAMES+=("${df#./}")
done

while IFS= read -r doc; do
  case "$doc" in
    ./CHANGELOG.md|./tests/*) continue ;;
  esac

  # A `docker build` whose context argument is `.` (or `..`), i.e. this repo.
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    fail "$doc:$match builds an image with this repository as the context; this repo ships no core sources — prepare the pinned context and build against .build/core"
  done < <(grep -nE 'docker (buildx )?build[^|]*(-t|--tag)[^|]*[[:space:]]\.\.?[[:space:]]*$' "$doc" || true)

  # A build that names one of the core-compiling Dockerfiles must use the
  # prepared context.
  for name in "${CORE_DOCKERFILE_NAMES[@]}"; do
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      # shellcheck disable=SC2016  # matching the literal text of a build command
      case "$match" in
        *".build/core"*|*'$(CORE_CONTEXT)'*|*'${CORE_CONTEXT}'*) ;;
        *) fail "$doc:$match builds $name without the prepared core context (.build/core)" ;;
      esac
    done < <(grep -nE "docker (buildx )?build.*-f ${name//./\\.}" "$doc" || true)
  done
done < <(find . -path ./.git -prune -o -path ./.build -prune -o -type f -name '*.md' -print | sort)

# The raw-manifest docs are the ones that shipped the broken instruction, so
# pin their corrected form explicitly.
if [ -f k8s/README.md ]; then
  grep -Eq 'scripts/prepare-core-context\.sh|make core-context' k8s/README.md \
    || fail "k8s/README.md must tell operators to prepare the pinned core context before building"
  grep -Fq 'docker build -f Dockerfile .build/core' k8s/README.md \
    || fail "k8s/README.md must build with 'docker build -f Dockerfile .build/core', not with this repository as the context"
fi

# --- Removed duplicate image definitions must stay removed ------------------
for stale in docker/Dockerfile.release docker/Dockerfile.optimized; do
  [ -e "$stale" ] && fail "$stale was removed as a duplicate image definition"
  # CHANGELOG entries legitimately name removed files.
  if git grep -Fq -- "$stale" -- . \
      ':!tests/dockerfile-context_test.sh' ':!CHANGELOG.md' 2>/dev/null; then
    fail "$stale is still referenced but no longer exists"
  fi
done

# --- The overlay the edge image depends on is actually produced -------------
# Dockerfile.edge bakes in a config file that lives here, not in core, so the
# prepared context has to carry it. If either side of that contract moves, the
# edge build breaks only at `docker build` time.
if grep -q '^COPY \.deploy/' Dockerfile.edge; then
  overlay_path="$(grep -oE '^COPY \.deploy/[^ ]+' Dockerfile.edge | head -n 1 | sed 's|^COPY \.deploy/||')"
  [ -f "$overlay_path" ] \
    || fail "Dockerfile.edge copies .deploy/$overlay_path but $overlay_path is not in this repository"
  grep -Fq '.deploy' scripts/prepare-core-context.sh \
    || fail "scripts/prepare-core-context.sh must write the .deploy/ overlay Dockerfile.edge copies from"
fi

# --- The pin itself is either unset (fail-closed) or an immutable SHA -------
pinned_ref="$(grep -E '^STREAMLINE_CORE_REF=' core-source.env | cut -d= -f2-)"
if [ -n "$pinned_ref" ] && ! printf '%s' "$pinned_ref" | grep -Eq '^[0-9a-f]{40}$'; then
  fail "core-source.env pins '$pinned_ref', which is not a 40-character commit SHA"
fi

echo "dockerfile-context gate passed"
