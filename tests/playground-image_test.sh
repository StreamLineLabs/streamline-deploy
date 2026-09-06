#!/usr/bin/env bash
# Static gate: the playground image's start-up contract holds.
#
# The image runs as UID 1000 and used to have no /data at all: the directory was
# never created, so nothing owned it. That is invisible until something writes —
# the playground defaults to in-memory storage — and then the container dies on
# a permission error that looks like a Streamline bug. A non-root process cannot
# create a directory at the filesystem root at run time, so the fix has to
# happen at build time, before USER.
#
# The contract this gate pins:
#   * /data exists, is owned by the runtime user, and is created BEFORE the
#     image switches away from root;
#   * STREAMLINE_DATA_DIR points at it, so the server and the operator agree
#     where data lives;
#   * the image still runs non-root;
#   * the health check and the start command are explicit, and the health check
#     has the tool it needs.
#
# Hermetic: pure text inspection of the Dockerfile and the compose stack that
# names the image. It runs no networked build — `docker build` here would fetch
# a Rust toolchain and compile core.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DOCKERFILE=playground/Dockerfile
COMPOSE=playground/docker-compose.playground.yml

status=0

fail() {
  echo "FAIL: $*" >&2
  status=1
}

[ -f "$DOCKERFILE" ] || { echo "FAIL: $DOCKERFILE is missing" >&2; exit 1; }

# Line number of the first match, or 0.
line_of() {
  grep -nE "$1" "$DOCKERFILE" | head -n 1 | cut -d: -f1 || true
}

# ---------------------------------------------------------------------------
# 1. Writable data directory, owned by the runtime user, created before USER
# ---------------------------------------------------------------------------
mkdir_line="$(line_of '^RUN[[:space:]]+mkdir[[:space:]]+-p[[:space:]]+/data')"
[ -n "$mkdir_line" ] \
  || fail "$DOCKERFILE must create /data (a non-root container cannot create it at run time)"

grep -Eq '^RUN[[:space:]]+mkdir[[:space:]]+-p[[:space:]]+/data[[:space:]]+&&[[:space:]]+chown[[:space:]]+-R[[:space:]]+streamline:streamline[[:space:]]+/data' "$DOCKERFILE" \
  || fail "$DOCKERFILE must chown /data to the streamline user, or UID 1000 cannot write to it"

useradd_line="$(line_of '^RUN[[:space:]]+groupadd')"
[ -n "$useradd_line" ] \
  || fail "$DOCKERFILE must create the non-root streamline user"

user_line="$(line_of '^USER[[:space:]]')"
[ -n "$user_line" ] || fail "$DOCKERFILE must switch to a non-root user"

if [ -n "$mkdir_line" ] && [ -n "$user_line" ] && [ "$mkdir_line" -gt "$user_line" ]; then
  fail "$DOCKERFILE creates /data after USER (line $mkdir_line > $user_line); the switch to UID 1000 makes that impossible"
fi
if [ -n "$mkdir_line" ] && [ -n "$useradd_line" ] && [ "$mkdir_line" -lt "$useradd_line" ]; then
  fail "$DOCKERFILE chowns /data to a user that does not exist yet (line $mkdir_line < $useradd_line)"
fi

grep -Eq '^[[:space:]]*STREAMLINE_DATA_DIR=/data' "$DOCKERFILE" \
  || fail "$DOCKERFILE must set STREAMLINE_DATA_DIR=/data so the server writes where the image prepared space"

# ---------------------------------------------------------------------------
# 2. Non-root stays non-root
# ---------------------------------------------------------------------------
grep -Eq '^USER[[:space:]]+1000(:1000)?[[:space:]]*$' "$DOCKERFILE" \
  || fail "$DOCKERFILE must run as UID 1000, matching the official image and the chart's securityContext"
if awk -v start="${user_line:-0}" 'NR > start && /^USER[[:space:]]+(root|0)([[:space:]]|:|$)/ { found = 1 } END { exit found ? 0 : 1 }' "$DOCKERFILE"; then
  fail "$DOCKERFILE switches back to root after dropping privileges"
fi

# ---------------------------------------------------------------------------
# 3. Health check and start command are explicit and usable
# ---------------------------------------------------------------------------
health="$(grep -E '^HEALTHCHECK' "$DOCKERFILE" || true)"
[ -n "$health" ] || fail "$DOCKERFILE must declare a HEALTHCHECK"
case "$health" in
  *9094*) ;;
  *) fail "$DOCKERFILE's HEALTHCHECK must probe the HTTP API port 9094, got: $health" ;;
esac
case "$health" in
  *health*) ;;
  *) fail "$DOCKERFILE's HEALTHCHECK must call a health endpoint, got: $health" ;;
esac
case "$health" in
  *curl*)
    grep -Fq 'curl' "$DOCKERFILE" \
      || fail "$DOCKERFILE's HEALTHCHECK uses curl but never installs it" ;;
esac
grep -Eq 'apt-get install .*(\\\\)?$|curl' "$DOCKERFILE" \
  || fail "$DOCKERFILE must install the tool its HEALTHCHECK invokes"

grep -Eq '^ENTRYPOINT \["streamline"\]' "$DOCKERFILE" \
  || fail "$DOCKERFILE must start the streamline binary explicitly"
cmd="$(grep -E '^CMD ' "$DOCKERFILE" || true)"
[ -n "$cmd" ] || fail "$DOCKERFILE must declare a CMD, so the default arguments are visible in docker inspect"
case "$cmd" in
  *--data-dir*/data*) ;;
  *) fail "$DOCKERFILE's CMD must name the prepared data directory (--data-dir /data), got: $cmd" ;;
esac

grep -Eq '^EXPOSE .*9092' "$DOCKERFILE" \
  || fail "$DOCKERFILE must expose the Kafka port 9092"
grep -Eq '^EXPOSE .*9094' "$DOCKERFILE" \
  || fail "$DOCKERFILE must expose the HTTP port 9094"

# The context contract is shared with the other core-compiling images.
grep -Fq 'prepare-core-context.sh' "$DOCKERFILE" \
  || fail "$DOCKERFILE must document the prepared core build context"

# ---------------------------------------------------------------------------
# 4. The compose stack that runs it agrees with the image
# ---------------------------------------------------------------------------
if [ -f "$COMPOSE" ]; then
  image_line="$(grep -E '^[[:space:]]*image:' "$COMPOSE" | head -n 1)"
  # shellcheck disable=SC2016  # the compose file literally contains ${STREAMLINE_PLAYGROUND_IMAGE}
  case "$image_line" in
    *'${STREAMLINE_PLAYGROUND_IMAGE'*) ;;
    *) fail "$COMPOSE must take its image from \${STREAMLINE_PLAYGROUND_IMAGE}; no playground image is published, got: $image_line" ;;
  esac
  case "$image_line" in
    *ghcr.io*|*streamlinelabs*) fail "$COMPOSE names a published image; none exists" ;;
  esac
  # The image ENTRYPOINT is the binary; repeating it in `command:` passed
  # "streamline" to itself as an argument.
  if grep -Eq '^[[:space:]]+(streamline|- streamline)[[:space:]]*$' "$COMPOSE"; then
    fail "$COMPOSE repeats the binary name in command:; the ENTRYPOINT already is the streamline binary"
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "playground-image gate passed: /data prepared and owned before USER, data dir/health/start command explicit"
fi

exit "$status"
