#!/usr/bin/env bash
# Static gate: the publisher must validate a digest BEFORE any public tag exists.
#
# The old pipeline pushed `{{version}}`, `{{major}}.{{minor}}` and `latest` in
# the very first step (docker/metadata-action → build-push-action) and only then
# ran the smoke test, the vulnerability scan, the SBOM and the signature. Every
# validation was therefore an after-the-fact opinion about bits users could
# already pull: a failing scan left a released tag in place, and the smoke test
# it did run could not fail anything meaningful because the release had already
# happened. The smoke test also swallowed its topic creation (`|| true`), so the
# produce/consume assertions ran against a topic that may never have existed.
#
# The pipeline is now: push ONE staging reference → validate the resulting
# DIGEST (smoke, scan, SBOM, signature, attestations) → promote that exact
# digest onto the public tags → verify each tag resolves back to it. This gate
# holds that shape: ordering, digest identity, and no escape hatches.
#
# Hermetic: pure text inspection, no registry, network, docker or cosign.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PUBLISHER=".github/workflows/docker-publish.yml"
SMOKE="docker-compose.test.yml"
BUILD_JOB="build-and-verify"
CONTRACT_JOB="release-contract"
PROMOTE_JOB="promote"
SLSA_JOB="slsa-provenance"

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

for f in "$PUBLISHER" "$SMOKE"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing" >&2; exit 1; }
done

# Body of a top-level job (two-space indented key under `jobs:`), with comment
# lines dropped: a comment sits *above* the step it describes, so counting it as
# content would attribute it to the previous step — and this file explains its
# ordering in prose that names the very steps being ordered.
job_block() {
  awk -v job="  $1:" '
    $0 == job { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { inside = 0 }
    inside && /^[[:space:]]*#/ { next }
    inside { print }
  ' "$PUBLISHER"
}

# The whole file without comment lines, for "this must not appear" checks.
config_lines() {
  grep -vE '^[[:space:]]*#' "$1"
}

# 1-based position of the first step in a job whose block matches a pattern.
# Steps are `      - ` items; everything until the next step belongs to it.
step_index() {
  # step_index <job block> <extended regex>
  printf '%s\n' "$1" | awk -v pattern="$2" '
    /^      - / { step++ }
    step > 0 && $0 ~ pattern && !found { found = step }
    END { print found + 0 }
  '
}

build_job="$(job_block "$BUILD_JOB")"
contract_job="$(job_block "$CONTRACT_JOB")"
promote_job="$(job_block "$PROMOTE_JOB")"
slsa_job="$(job_block "$SLSA_JOB")"

[ -n "$contract_job" ] || fail "$PUBLISHER must define a '$CONTRACT_JOB' job that binds the tag to pinned core metadata"
[ -n "$build_job" ] || fail "$PUBLISHER must define a '$BUILD_JOB' job that builds and validates before publishing"
[ -n "$promote_job" ] || fail "$PUBLISHER must define a '$PROMOTE_JOB' job that publishes the validated digest"
[ -n "$slsa_job" ] || fail "$PUBLISHER must define a '$SLSA_JOB' job for release provenance"

# A manual dispatch may select an existing tag ref, so checking github.ref
# alone does not distinguish a maintainer's validation run from a release-tag
# push. Public writes require both predicates on the job itself.
require_release_push_guard() {
  # require_release_push_guard <job name> <job block>
  local job_name="$1"
  local block="$2"
  local guard

  guard="$(printf '%s\n' "$block" | grep -E '^    if:' || true)"
  [ "$(printf '%s\n' "$guard" | grep -c . || true)" -eq 1 ] \
    || { fail "$job_name must have exactly one job-level release guard"; return; }
  printf '%s\n' "$guard" \
    | grep -Fq "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')" \
    || fail "$job_name must require a push event AND a version tag; workflow_dispatch is validation-only"
}

grep -Fq 'workflow_dispatch:' "$PUBLISHER" \
  || fail "$PUBLISHER must keep a manual validation entry point"
grep -Fq 'core_ref:' "$PUBLISHER" \
  || fail "$PUBLISHER must keep the validation-only core_ref override"
if printf '%s\n' "$build_job" | grep -Eq '^    if:'; then
  fail "$BUILD_JOB must stay available to workflow_dispatch validation runs"
fi
require_release_push_guard "$PROMOTE_JOB" "$promote_job"
require_release_push_guard "$SLSA_JOB" "$slsa_job"

for public_job in "$promote_job" "$slsa_job"; do
  # shellcheck disable=SC2016  # match the literal workflow expression
  if printf '%s\n' "$public_job" | grep -Fq '${{ inputs.core_ref }}'; then
    fail "a public release job reads inputs.core_ref directly; manual overrides must never reach promotion"
  fi
done

# ---------------------------------------------------------------------------
# 0. A release tag is bound to the pinned core package version before build
# ---------------------------------------------------------------------------
if [ -n "$contract_job" ]; then
  printf '%s\n' "$contract_job" | grep -Fq 'RELEASE_TAG: ${{ github.ref_name }}' \
    || fail "$CONTRACT_JOB must pass the push tag through the environment"
  printf '%s\n' "$contract_job" | grep -Fq '"${CORE_CONTEXT}/Cargo.toml"' \
    || fail "$CONTRACT_JOB must read the pinned core Cargo.toml"
  printf '%s\n' "$contract_job" | grep -Fq 'tag_version="${RELEASE_TAG#v}"' \
    || fail "$CONTRACT_JOB must derive the image version from the v-prefixed push tag"
  printf '%s\n' "$contract_job" | grep -Fq 'tag_version}" != "${core_version}' \
    || fail "$CONTRACT_JOB must require the push tag and pinned core Cargo version to match exactly"
  printf '%s\n' "$contract_job" | grep -Fq 'version=${version}' \
    || fail "$CONTRACT_JOB must expose the verified exact release version"
fi

printf '%s\n' "$build_job" | grep -Eq "needs:.*$CONTRACT_JOB" \
  || fail "$BUILD_JOB must depend on $CONTRACT_JOB before building"
printf '%s\n' "$build_job" | grep -Fq 'STREAMLINE_VERSION=${{ needs.release-contract.outputs.version }}' \
  || fail "$BUILD_JOB must pass the exact verified STREAMLINE_VERSION build argument"
printf '%s\n' "$build_job" | grep -Fq 'org.opencontainers.image.version=${{ needs.release-contract.outputs.version }}' \
  || fail "$BUILD_JOB must label the image with the exact verified release version"
printf '%s\n' "$build_job" | grep -Fq 'org.opencontainers.image.version' \
  || fail "$BUILD_JOB must inspect the staged image's OCI version label"
printf '%s\n' "$build_job" | grep -Fq 'actual_version}" != "${EXPECTED_VERSION}' \
  || fail "$BUILD_JOB must reject a staged image whose OCI version label differs from the verified release version"

# ---------------------------------------------------------------------------
# 1. The first push writes a staging reference, never a public tag
# ---------------------------------------------------------------------------
if [ -n "$build_job" ]; then
  printf '%s\n' "$build_job" | grep -Fq 'staging-' \
    || fail "$BUILD_JOB must push a staging reference (staging-<run id>-<attempt>), not a release tag"

  if printf '%s\n' "$build_job" | grep -Fq 'docker/metadata-action'; then
    fail "$BUILD_JOB must not run docker/metadata-action: computing the public tag list next to the initial push is how unvalidated bits reached 'latest'"
  fi

  # The tags fed to the initial push must come from the staging step only.
  build_tags="$(printf '%s\n' "$build_job" | grep -E '^[[:space:]]+tags:' || true)"
  [ -n "$build_tags" ] || fail "$BUILD_JOB has no tags: on its build step"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"steps.staging.outputs.ref"*) ;;
      *) fail "$BUILD_JOB pushes tags that do not come from the staging step: $line" ;;
    esac
  done <<EOF
$build_tags
EOF

  for public_tag in 'type=semver' 'value=latest' '{{version}}' '{{major}}'; do
    if printf '%s\n' "$build_job" | grep -Fq "$public_tag"; then
      fail "$BUILD_JOB references a public tag pattern ($public_tag); public tags are only written after validation, in $PROMOTE_JOB"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 2. Every validation runs against the digest, in the right order
# ---------------------------------------------------------------------------
if [ -n "$build_job" ]; then
  printf '%s\n' "$build_job" | grep -Fq 'steps.build.outputs.digest' \
    || fail "$BUILD_JOB must capture the digest the build produced"
  printf '%s\n' "$build_job" | grep -Fq 'sha256:' \
    || fail "$BUILD_JOB must verify the build really returned a sha256 digest before validating it"

  build_step="$(step_index "$build_job" 'docker/build-push-action')"
  digest_step="$(step_index "$build_job" 'id: digest')"
  smoke_step="$(step_index "$build_job" 'docker-compose.test.yml')"
  scan_step="$(step_index "$build_job" 'trivy-action')"
  sign_step="$(step_index "$build_job" 'cosign sign')"
  sbom_step="$(step_index "$build_job" 'sbom-action')"
  attest_step="$(step_index "$build_job" 'cosign attest')"
  provenance_step="$(step_index "$build_job" 'attest-build-provenance')"

  for pair in \
    "build:$build_step" "digest:$digest_step" "smoke:$smoke_step" "scan:$scan_step" \
    "sign:$sign_step" "sbom:$sbom_step" "attest:$attest_step" "provenance:$provenance_step"; do
    name="${pair%%:*}"; index="${pair##*:}"
    [ "$index" -gt 0 ] 2>/dev/null || fail "$BUILD_JOB has no $name step"
  done

  ordered() {
    # ordered <name a> <index a> <name b> <index b>
    if [ "${2:-0}" -gt 0 ] && [ "${4:-0}" -gt 0 ] && [ "$2" -ge "$4" ]; then
      fail "$BUILD_JOB runs $3 (step $4) before $1 (step $2); validation must follow the build it validates"
    fi
  }
  ordered build "$build_step" digest "$digest_step"
  ordered digest "$digest_step" smoke "$smoke_step"
  ordered smoke "$smoke_step" scan "$scan_step"
  ordered scan "$scan_step" sign "$sign_step"
  ordered sign "$sign_step" sbom "$sbom_step"
  ordered sbom "$sbom_step" attest "$attest_step"
  ordered attest "$attest_step" provenance "$provenance_step"

  # Each validation must name the digest, not a tag that could be re-pointed.
  # Step inputs only (indented under `with:`/`env:`), not the job's `outputs:`
  # block, which legitimately exposes the bare repository name.
  digest_users="$(printf '%s\n' "$build_job" | grep -nE '^[[:space:]]{10,}(image|image-ref|STREAMLINE_IMAGE|DIGEST_REF|subject-digest):' || true)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"steps.digest.outputs"*) ;;
      *"subject-digest"*) ;;
      *) fail "$BUILD_JOB validates something that is not the pinned digest: $line" ;;
    esac
  done <<EOF
$digest_users
EOF

  printf '%s\n' "$build_job" | grep -Fq "exit-code: '1'" \
    || fail "$BUILD_JOB's vulnerability scan must fail the job (exit-code: '1'), or it cannot block a release"

  printf '%s\n' "$build_job" | grep -Fq 'platforms: linux/amd64' \
    || fail "$BUILD_JOB must publish only linux/amd64 until every additional platform has its own smoke and scan lane"
  if printf '%s\n' "$build_job" | grep -Eq 'platforms:.*arm64'; then
    fail "$BUILD_JOB publishes arm64 without an arm64 smoke test and vulnerability scan"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Promotion happens afterwards and copies THE SAME digest
# ---------------------------------------------------------------------------
if [ -n "$promote_job" ]; then
  printf '%s\n' "$promote_job" | grep -Eq "needs:.*$BUILD_JOB" \
    || fail "$PROMOTE_JOB must declare 'needs: [$BUILD_JOB]' — that dependency is the ordering guarantee"

  if printf '%s\n' "$promote_job" | grep -Fq 'build-push-action'; then
    fail "$PROMOTE_JOB must not rebuild: a rebuild publishes bits that were never scanned or signed"
  fi

  printf '%s\n' "$promote_job" | grep -Fq 'imagetools create' \
    || fail "$PROMOTE_JOB must promote by copying the manifest (docker buildx imagetools create)"
  printf '%s\n' "$promote_job" | grep -Fq "needs.$BUILD_JOB.outputs.digest_ref" \
    || fail "$PROMOTE_JOB must promote the digest reference produced by $BUILD_JOB"
  printf '%s\n' "$promote_job" | grep -Fq 'imagetools inspect' \
    || fail "$PROMOTE_JOB must verify the published tags after promoting them"
  printf '%s\n' "$promote_job" | grep -Fq 'not the validated digest' \
    || fail "$PROMOTE_JOB must fail when a published tag resolves to a different digest"
  printf '%s\n' "$promote_job" | grep -Fq 'refusing to promote' \
    || fail "$PROMOTE_JOB must fail closed when no public tag was computed, instead of publishing nothing quietly"

  printf '%s\n' "$promote_job" | grep -Fq 'docker/metadata-action' \
    || fail "$PROMOTE_JOB should compute the public tag list (docker/metadata-action) at promotion time"
  latest_rule="$(printf '%s\n' "$promote_job" | grep -F 'type=raw,value=latest' || true)"
  printf '%s\n' "$latest_rule" \
    | grep -Fq "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')" \
    || fail "$PROMOTE_JOB must not compute latest for workflow_dispatch, even when the selected ref is a version tag"
fi

# ---------------------------------------------------------------------------
# 4. No escape hatches anywhere in the publisher
# ---------------------------------------------------------------------------
if config_lines "$PUBLISHER" | grep -Fq 'continue-on-error'; then
  fail "$PUBLISHER must not use continue-on-error"
fi
if config_lines "$PUBLISHER" | grep -Fq '|| true'; then
  fail "$PUBLISHER must not swallow a command's failure with '|| true'"
fi

# `if:` is allowed on jobs and on the SARIF upload (which must run even when the
# scan failed the job); anywhere else it is a way to skip a validation.
while IFS= read -r line; do
  case "$line" in
    *"if: always()"*) ;;                                   # SARIF upload
    *"if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')"*) ;; # job-level release guard
    *) fail "$PUBLISHER guards a step with a condition that could skip a validation: $line" ;;
  esac
done < <(config_lines "$PUBLISHER" | grep -E '^[[:space:]]+if:' || true)

# ---------------------------------------------------------------------------
# 5. The smoke test the publisher runs actually asserts something
# ---------------------------------------------------------------------------
if config_lines "$SMOKE" | grep -Fq '|| true'; then
  fail "$SMOKE must not swallow failures with '|| true': the create/produce/consume assertions have to execute"
fi
for assertion in 'topics create' 'topics list' 'produce' 'consume'; do
  grep -Fq "$assertion" "$SMOKE" \
    || fail "$SMOKE must exercise '$assertion'"
done
grep -Fq 'Created topic is missing from the topic listing' "$SMOKE" \
  || fail "$SMOKE must assert the created topic appears in the listing, not just that the command ran"
grep -Fq 'Message verification failed' "$SMOKE" \
  || fail "$SMOKE must assert the consumed message matches what was produced"
grep -Eq 'set -eu' "$SMOKE" \
  || fail "$SMOKE must run under 'set -eu' so an unchecked command cannot pass silently"
grep -Fq 'did not become healthy' "$SMOKE" \
  || fail "$SMOKE must bound its health wait and fail, rather than hang, when the server never starts"

if [ "$status" -eq 0 ]; then
  echo "publish-pipeline gate passed: staged digest validated before any public tag, promoted by digest identity"
fi

exit "$status"
