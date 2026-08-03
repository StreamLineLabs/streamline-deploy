#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CURL_LOG"
EOF
chmod +x "$TMP_DIR/bin/curl"

OUTPUT="$(
  cd "$REPO_ROOT"
  CURL_LOG="$TMP_DIR/curl.log" \
    PATH="$TMP_DIR/bin:$PATH" \
    STREAMLINE_HOST="seed-test" \
    STREAMLINE_HTTP_PORT="19094" \
    bash docker/seed-data.sh
)"

grep -Fq "Topics created:  4" <<<"$OUTPUT"
grep -Fq "Messages seeded: 40" <<<"$OUTPUT"
grep -Fq "demo-events" <<<"$OUTPUT"
grep -Fq "demo-orders" <<<"$OUTPUT"

test "$(grep -c '/health' "$TMP_DIR/curl.log")" -eq 1
test "$(grep -c '/v1/topics ' "$TMP_DIR/curl.log")" -eq 4
test "$(grep -c '/messages ' "$TMP_DIR/curl.log")" -eq 40

echo "seed-data characterization passed"
