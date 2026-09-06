#!/usr/bin/env bash
# Static gate: nothing may present an unpublished artifact as installable.
#
# No Streamline image exists. `core-source.env` pins no core commit, so the
# single publisher (.github/workflows/docker-publish.yml) has never built or
# pushed anything, and no Helm chart has been published to a repository either.
# The artifacts nevertheless told users to `docker pull
# ghcr.io/streamlinelabs/streamline:0.3.0`, defaulted every Compose stack to
# that tag, pinned it in the raw manifests and shipped it as the chart's
# `image.tag`. Each one fails at pull time with `manifest unknown` — after the
# reader has followed a "Try it in 10 seconds" instruction and concluded the
# project is broken.
#
# Rule: a deployment default either names an artifact that exists, or it is a
# local-only placeholder that cannot be pulled (no registry path), forcing the
# operator to supply an image they built. Version strings themselves are not the
# problem and are not changed here; the *claim that they are pullable* is.
#
# Hermetic: pure text inspection. No registry, network or docker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

config_lines() {
  grep -vE '^[[:space:]]*#' "$1"
}

# Files that legitimately record history or test these very strings.
skip_file() {
  case "$1" in
    ./CHANGELOG.md|CHANGELOG.md|./tests/*|tests/*|./AUDIT.md|AUDIT.md) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 1. No Compose stack may default to a pullable Streamline image
# ---------------------------------------------------------------------------
shopt -s nullglob
compose_files=(docker-compose*.yml */docker-compose*.yml docker/docker-compose*.yml)
shopt -u nullglob
[ "${#compose_files[@]}" -gt 0 ] || fail "no docker-compose*.yml found"

for compose in "${compose_files[@]}"; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ref="$(printf '%s' "${line#*image:}" | tr -d ' "')"
    # shellcheck disable=SC2016  # a Compose interpolation is literal text here
    case "$ref" in
      '${'*) ;;
      *) fail "$compose hard-codes the Streamline image '$ref'; no image is published, so it must come from a variable with an unpullable local default" ; continue ;;
    esac
    default="${ref#*:-}"
    default="${default%\}}"
    if [ "$default" = "$ref" ]; then
      fail "$compose uses a Streamline image variable with no default; \`docker compose config\` must stay valid with no environment set"
      continue
    fi
    case "$default" in
      */*) fail "$compose defaults to '$default', a pullable registry reference; nothing publishes it" ;;
      *ghcr.io*|*streamlinelabs*|*docker.io*) fail "$compose defaults to a published-looking image '$default'" ;;
    esac
    case "$default" in
      *:*) ;;
      *) fail "$compose default '$default' has no tag; an implicit :latest is exactly the pull that fails" ;;
    esac
  done < <(config_lines "$compose" | grep -E '^[[:space:]]*image:.*[Ss]treamline' || true)
done

# ---------------------------------------------------------------------------
# 2. The chart ships no default tag
# ---------------------------------------------------------------------------
VALUES=helm/streamline/values.yaml
HELPERS=helm/streamline/templates/_helpers.tpl
if [ -f "$VALUES" ]; then
  tag_line="$(grep -E '^[[:space:]]+tag:' "$VALUES" | head -n 1)"
  case "$tag_line" in
    *'tag: ""'*) ;;
    *) fail "$VALUES must ship an empty image.tag until an image is published, got: $tag_line" ;;
  esac
fi
if [ -f "$HELPERS" ]; then
  grep -Fq 'define "streamline.imageRef"' "$HELPERS" \
    || fail "$HELPERS must define streamline.imageRef so an empty tag fails the render"
  grep -Fq 'image.tag is empty and this chart ships no default tag' "$HELPERS" \
    || fail "$HELPERS must explain why there is no default tag when it refuses to render"
fi
STATEFULSET=helm/streamline/templates/statefulset.yaml
if [ -f "$STATEFULSET" ]; then
  grep -Fq 'include "streamline.imageRef"' "$STATEFULSET" \
    || fail "$STATEFULSET must build its image reference through streamline.imageRef"
fi

# ---------------------------------------------------------------------------
# 3. Raw manifests carry an unpullable placeholder, not a release tag
# ---------------------------------------------------------------------------
while IFS= read -r manifest; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ref="$(printf '%s' "${line#*image:}" | tr -d ' "')"
    case "$ref" in
      *ghcr.io/streamlinelabs/*|*docker.io/streamlinelabs/*)
        fail "$manifest references '$ref', which nothing publishes; use an unpullable placeholder and document the override" ;;
    esac
  done < <(config_lines "$manifest" | grep -E '^[[:space:]-]*image:' || true)
done < <(find k8s playground -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)

if [ -f k8s/kustomization.yaml ]; then
  grep -Fq 'set-image-before-apply' k8s/kustomization.yaml \
    || fail "k8s/kustomization.yaml must keep the unpullable placeholder tag until an image is published"
fi

# ---------------------------------------------------------------------------
# 4. No document may hand out a pull/run command for an image nobody publishes
# ---------------------------------------------------------------------------
while IFS= read -r doc; do
  skip_file "$doc" && continue
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    fail "$doc:$match tells the reader to pull or run an unpublished image"
  done < <(grep -nE '(docker (run|pull)[^|]*|helm install[^|]*)(ghcr\.io/streamlinelabs/|streamlinelabs/)' "$doc" || true)

  # Multi-line commands hide the reference on a continuation line, so also flag
  # any *tagged* reference to the registry. Naming the registry itself is fine
  # ("images will be published to ghcr.io"); naming a tag there is the claim.
  NEGATION_RE='\bno\b|\bnot\b|never|nobody|will be|would|once (a )?(release|image)|unpublished|does not exist|placeholder'
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    printf '%s' "$match" | grep -Eqi -e "$NEGATION_RE" && continue
    fail "$doc:$match names a registry tag that nothing publishes"
  done < <(grep -nE '(ghcr\.io|docker\.io)/streamlinelabs/[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+' "$doc" || true)

  # A chart repository that does not exist is the same failure in Helm clothing.
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    case "$match" in
      *'#'*) continue ;;
    esac
    fail "$doc:$match points at a Helm chart repository that is not published"
  done < <(grep -nE '^[^#]*helm repo add' "$doc" || true)
done < <(find . -path ./.git -prune -o -path ./.build -prune -o -type f -name '*.md' -print | sort)

# ---------------------------------------------------------------------------
# 5. The placeholders stay unpullable
# ---------------------------------------------------------------------------
# A placeholder with a registry path in it would be pulled, not rejected.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *set-STREAMLINE*|*set-image-before-apply*|*demo-disabled*) ;;
    *) continue ;;
  esac
  case "$line" in
    *ghcr.io*|*docker.io*|*quay.io*)
      fail "a placeholder resolves to a registry path, so it would be pulled instead of failing: $line" ;;
  esac
done < <(grep -rhE 'set-STREAMLINE|set-image-before-apply|demo-disabled' \
  --include='*.yml' --include='*.yaml' . 2>/dev/null || true)

if [ "$status" -eq 0 ]; then
  echo "published-artifact gate passed: no stack, manifest, chart default or doc promises an image that does not exist"
fi

exit "$status"
