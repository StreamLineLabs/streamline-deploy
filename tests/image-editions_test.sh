#!/usr/bin/env bash
# Static gate: an image edition may not claim capabilities its build cannot have.
#
# "full" is a capability claim — the Helm chart reads it as "this image supports
# SASL auth and clustering" and lets those settings through. It used to accept
# *any* non-empty STREAMLINE_FEATURES, so `--build-arg STREAMLINE_EDITION=full
# --build-arg STREAMLINE_FEATURES=compression` produced an image labelled full
# that cargo had never compiled auth into. The chart then rendered an
# authenticated broker configuration onto a binary with no authentication.
#
# The contract is now:
#   standard — no STREAMLINE_FEATURES, no STREAMLINE_CAPABILITIES.
#   full     — STREAMLINE_FEATURES=full exactly (core's own meta-feature), which
#              is the only list known to back the auth/clustering claim.
#   custom   — any other list, and it MUST declare STREAMLINE_CAPABILITIES
#              (auth, clustering, moonshot or the literal "none"). The chart
#              infers nothing from a custom build: image.capabilities has to
#              mirror the declaration.
#
# Hermetic: pure text inspection of the Dockerfile, chart and docs. No docker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DOCKERFILE=Dockerfile
HELPERS=helm/streamline/templates/_helpers.tpl
SCHEMA=helm/streamline/values.schema.json
VALUES=helm/streamline/values.yaml

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

for f in "$DOCKERFILE" "$HELPERS" "$SCHEMA" "$VALUES"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. The image build enforces the contract
# ---------------------------------------------------------------------------
grep -Eq '^ARG STREAMLINE_EDITION' "$DOCKERFILE" \
  || fail "$DOCKERFILE must declare ARG STREAMLINE_EDITION"
grep -Eq '^ARG STREAMLINE_FEATURES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must declare ARG STREAMLINE_FEATURES"
grep -Eq '^ARG STREAMLINE_CAPABILITIES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must declare ARG STREAMLINE_CAPABILITIES so a custom build can state what it supports"

grep -Fq 'STREAMLINE_EDITION=full accepts only STREAMLINE_FEATURES=full' "$DOCKERFILE" \
  || fail "$DOCKERFILE must reject a full edition built with any feature list other than 'full'"
grep -Fq 'STREAMLINE_EDITION=custom requires STREAMLINE_FEATURES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must reject a custom edition with no feature list"
grep -Fq 'STREAMLINE_EDITION=custom requires STREAMLINE_CAPABILITIES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must require an explicit capability declaration for a custom edition"
grep -Fq 'STREAMLINE_EDITION=standard must not set STREAMLINE_FEATURES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must reject a standard edition with a feature list"
grep -Fq 'STREAMLINE_EDITION=standard must not set STREAMLINE_CAPABILITIES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must reject capability claims on the standard edition"
grep -Fq 'STREAMLINE_EDITION=full must not set STREAMLINE_CAPABILITIES' "$DOCKERFILE" \
  || fail "$DOCKERFILE must reject capability claims on the full edition (they follow from the feature set)"
grep -Fq "expected: standard, full, custom" "$DOCKERFILE" \
  || fail "$DOCKERFILE must fail closed on an unknown edition and name the accepted ones"
grep -Fq "expected: auth, clustering, moonshot, none" "$DOCKERFILE" \
  || fail "$DOCKERFILE must validate every declared capability name"

# The declaration has to survive into the image, or nothing can check it later.
grep -Fq 'dev.streamline.edition' "$DOCKERFILE" \
  || fail "$DOCKERFILE must label the image edition"
grep -Fq 'dev.streamline.features' "$DOCKERFILE" \
  || fail "$DOCKERFILE must label the compiled feature list"
grep -Fq 'dev.streamline.capabilities' "$DOCKERFILE" \
  || fail "$DOCKERFILE must label the declared capabilities so a deployment can be checked against them"

# The build entry point must be able to pass the declaration through.
grep -Fq 'STREAMLINE_CAPABILITIES' Makefile \
  || fail "Makefile's docker target must forward STREAMLINE_CAPABILITIES"

# ---------------------------------------------------------------------------
# 2. The guard actually behaves that way when executed
# ---------------------------------------------------------------------------
# Greps prove the messages exist; this runs the validation block itself. The
# RUN line is extracted, its continuations honoured, and the resulting POSIX
# script executed with the three build args set — no docker, no network, no
# image. A guard that reads correctly but accepts the wrong combination is
# exactly the failure this file exists to prevent.
GUARD_SCRIPT="$(awk '
  /^RUN set -eu; \\$/ { collecting = 1 }
  collecting { print }
  collecting && !/\\$/ { exit }
' "$DOCKERFILE" | sed '1s/^RUN //' | sed -e :a -e '/\\$/N; s/\\\n//; ta')"

[ -n "$GUARD_SCRIPT" ] || fail "could not extract the edition guard from $DOCKERFILE"

# edition | features | capabilities | expected exit (0 = accepted)
EDITION_CASES=(
  "standard|||0"
  "standard|cdc||1"
  "standard||auth|1"
  "full|full||0"
  "full|compression||1"
  "full|||1"
  "full|full|auth|1"
  "custom|cdc,analytics|none|0"
  "custom|cdc,analytics|auth,clustering|0"
  "custom|cdc||1"
  "custom||auth|1"
  "custom|full|auth|1"
  "custom|cdc|bogus|1"
  "enterprise|||1"
)

if [ -n "$GUARD_SCRIPT" ]; then
  for row in "${EDITION_CASES[@]}"; do
    IFS='|' read -r edition features capabilities expected <<<"$row"
    if STREAMLINE_EDITION="$edition" \
       STREAMLINE_FEATURES="$features" \
       STREAMLINE_CAPABILITIES="$capabilities" \
       sh -c "$GUARD_SCRIPT" >/dev/null 2>&1; then
      actual=0
    else
      actual=1
    fi
    if [ "$actual" != "$expected" ]; then
      if [ "$expected" = "0" ]; then
        fail "$DOCKERFILE rejects a valid combination (edition=$edition features='$features' capabilities='$capabilities')"
      else
        fail "$DOCKERFILE accepts edition=$edition features='$features' capabilities='$capabilities'; that image would claim capabilities its build may not have"
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# 3. The chart mirrors it and never guesses
# ---------------------------------------------------------------------------
grep -Fq 'image.edition=custom requires an explicit image.capabilities list' "$HELPERS" \
  || fail "$HELPERS must reject a custom edition that declares no capabilities"
grep -Fq 'image.capabilities is only accepted with image.edition=custom' "$HELPERS" \
  || fail "$HELPERS must reject an explicit capability list on the standard/full editions (two sources of truth)"
grep -Fq 'expected \"standard\", \"full\" or \"custom\"' "$HELPERS" \
  || fail "$HELPERS must reject an unknown edition and name the accepted ones"

# The auth/clustering mapping must belong to the full edition only. If it can be
# reached from the custom branch, the chart is guessing again.
if ! awk '
  /define "streamline.imageCapabilities"/ { inside = 1 }
  inside && /eq \$edition "full"/ { seen_full = 1 }
  inside && /^auth,clustering$/ { if (!seen_full) exit 1 }
  inside && /^\{\{- end \}\}$/ && seen_full { exit 0 }
  END { exit 0 }
' "$HELPERS"; then
  fail "$HELPERS derives auth/clustering outside the full-edition branch; a custom build must declare its own capabilities"
fi

python3 - "$SCHEMA" <<'PY' || status=1
import json, sys
schema = json.load(open(sys.argv[1]))
image = schema["properties"]["image"]["properties"]
ok = True
edition = image["edition"].get("enum")
if edition != ["standard", "full", "custom"]:
    print(f"FAIL: values.schema.json image.edition enum is {edition}, expected standard/full/custom", file=sys.stderr)
    ok = False
caps = image["capabilities"]["items"].get("enum", [])
for expected in ("auth", "clustering", "moonshot", "none"):
    if expected not in caps:
        print(f"FAIL: values.schema.json image.capabilities must allow {expected!r}", file=sys.stderr)
        ok = False
if "custom" not in image["capabilities"].get("description", ""):
    print("FAIL: values.schema.json must document that image.capabilities belongs to the custom edition", file=sys.stderr)
    ok = False
sys.exit(0 if ok else 1)
PY

grep -Fq 'custom' "$VALUES" \
  || fail "$VALUES must document the custom edition"

# ---------------------------------------------------------------------------
# 4. The docs describe the same three editions
# ---------------------------------------------------------------------------
for doc in README.md helm/README.md docker/README.md CLAUDE.md; do
  [ -f "$doc" ] || continue
  grep -Fq 'custom' "$doc" \
    || fail "$doc must document the custom edition; an operator who reads only this file would otherwise build 'full' with an arbitrary feature list"
done

if [ "$status" -eq 0 ]; then
  echo "image-edition gate passed: full means STREAMLINE_FEATURES=full, custom must declare its capabilities"
fi

exit "$status"
