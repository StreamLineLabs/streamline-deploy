#!/usr/bin/env bash

HOST="${STREAMLINE_HOST:-localhost}"
HTTP_PORT="${STREAMLINE_HTTP_PORT:-9094}"
BASE_URL="http://${HOST}:${HTTP_PORT}"

TOTAL_MESSAGES=0

wait_for_server() {
  echo "⏳ Waiting for Streamline to be ready at ${BASE_URL}/health ..."
  local retries=0
  until curl -sf "${BASE_URL}/health" > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ "$retries" -ge 60 ]; then
      echo "❌ Streamline did not become ready after 60 seconds"
      exit 1
    fi
    sleep 1
  done
  echo "✅ Streamline is healthy"
  echo ""
}

create_topic() {
  local topic="$1"
  local partitions="${2:-1}"
  echo "  Creating topic '${topic}' (partitions: ${partitions})..."
  curl -sf -X POST "${BASE_URL}/v1/topics" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${topic}\",\"partitions\":${partitions}}" \
    > /dev/null 2>&1 || true
}

produce_message() {
  local topic="$1"
  local message="$2"
  curl -sf -X POST "${BASE_URL}/v1/topics/${topic}/messages" \
    -H "Content-Type: application/json" \
    -d "{\"value\":$(echo "$message" | jq -Rs .)}" \
    > /dev/null 2>&1 || true
  TOTAL_MESSAGES=$((TOTAL_MESSAGES + 1))
}
