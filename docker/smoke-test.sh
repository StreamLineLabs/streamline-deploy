#!/bin/sh
set -eu

STREAMLINE_HTTP_URL="${STREAMLINE_HTTP_URL:-http://streamline:9094}"
SMOKE_TOPIC="${SMOKE_TOPIC:-smoke-test}"
SMOKE_PARTITIONS=2
SMOKE_KEY="smoke-key"
SMOKE_VALUE="streamline-http-smoke-payload-v1"
SMOKE_HEADER_KEY="smoke-test"
SMOKE_HEADER_VALUE="true"

assert_health_response() {
  jq --slurp --exit-status '
    length == 1
    and (
      .[0]
      | type == "object"
        and keys == ["checks", "status"]
        and .status == "healthy"
        and (.checks | type == "array" and length > 0)
        and all(
          .checks[];
          type == "object"
          and keys == ["name", "status"]
          and (.name | type == "string" and length > 0)
          and .status == "ok"
        )
        and (([.. | objects | has("error")] | any) | not)
    )
  ' >/dev/null
}

assert_create_response() {
  jq --slurp --exit-status \
    --arg topic "$SMOKE_TOPIC" \
    --argjson partitions "$SMOKE_PARTITIONS" '
      length == 1
      and (
        .[0]
        | type == "object"
          and keys == [
            "bytes_per_second",
            "config",
            "is_internal",
            "messages_per_second",
            "name",
            "partition_count",
            "partitions",
            "replication_factor",
            "total_bytes",
            "total_messages"
          ]
          and .name == $topic
          and .partition_count == $partitions
          and (.replication_factor | type == "number" and floor == . and . >= 1)
          and (.is_internal | type == "boolean")
          and (
            .partitions
            | type == "array"
              and length == $partitions
              and all(
                .[];
                type == "object"
                and keys == [
                  "end_offset",
                  "isr",
                  "leader",
                  "partition_id",
                  "replicas",
                  "size_bytes",
                  "start_offset"
                ]
                and (.partition_id | type == "number" and floor == . and . >= 0)
                and (
                  .leader == null
                  or (.leader | type == "number" and floor == . and . >= 0)
                )
                and (
                  .replicas
                  | type == "array"
                    and length > 0
                    and all(.[]; type == "number" and floor == . and . >= 0)
                )
                and (
                  .isr
                  | type == "array"
                    and length > 0
                    and all(.[]; type == "number" and floor == . and . >= 0)
                )
                and (.start_offset | type == "number" and floor == . and . >= 0)
                and (.end_offset | type == "number" and floor == . and . >= 0)
                and (.size_bytes | type == "number" and floor == . and . >= 0)
              )
              and ([.[].partition_id] | sort == [range(0; $partitions)])
          )
          and (
            .config
            | type == "object"
              and all(.[]; type == "string")
          )
          and (.total_messages | type == "number" and floor == . and . >= 0)
          and (.total_bytes | type == "number" and floor == . and . >= 0)
          and (.messages_per_second | type == "number")
          and (.bytes_per_second | type == "number")
          and (([.. | objects | has("error")] | any) | not)
      )
    ' >/dev/null
}

assert_topic_list_response() {
  jq --slurp --exit-status \
    --arg topic "$SMOKE_TOPIC" \
    --argjson partitions "$SMOKE_PARTITIONS" '
      length == 1
      and (
        .[0]
        | type == "array"
          and all(
            .[];
            type == "object"
            and keys == [
              "is_internal",
              "name",
              "partition_count",
              "replication_factor",
              "total_bytes",
              "total_messages"
            ]
            and (.name | type == "string" and length > 0)
            and (.partition_count | type == "number" and floor == . and . >= 1)
            and (.replication_factor | type == "number" and floor == . and . >= 1)
            and (.is_internal | type == "boolean")
            and (.total_messages | type == "number" and floor == . and . >= 0)
            and (.total_bytes | type == "number" and floor == . and . >= 0)
          )
          and (
            map(
              select(
                .name == $topic
                and .partition_count == $partitions
              )
            )
            | length == 1
          )
          and (([.. | objects | has("error")] | any) | not)
      )
    ' >/dev/null
}

extract_produced_offset() {
  jq --slurp --exit-status --raw-output '
    select(
      length == 1
      and (
        .[0]
        | type == "object"
          and keys == ["offsets"]
          and (.offsets | type == "array" and length == 1)
          and (
            .offsets[0]
            | type == "object"
              and keys == ["offset", "partition"]
              and .partition == 0
              and (.offset | type == "number" and . >= 0 and floor == .)
          )
          and (([.. | objects | has("error")] | any) | not)
      )
    )
    | .[0].offsets[0].offset
  '
}

assert_consume_response() {
  jq --slurp --exit-status \
    --arg topic "$SMOKE_TOPIC" \
    --arg key "$SMOKE_KEY" \
    --arg value "$SMOKE_VALUE" \
    --arg header_key "$SMOKE_HEADER_KEY" \
    --arg header_value "$SMOKE_HEADER_VALUE" \
    --argjson expected_offset "$1" '
      length == 1
      and (
        .[0]
        | type == "object"
          and keys == ["next_offset", "partition", "records", "topic"]
          and .topic == $topic
          and .partition == 0
          and .next_offset == ($expected_offset + 1)
          and (.records | type == "array" and length == 1)
          and (
            .records[0]
            | type == "object"
              and keys == ["headers", "key", "offset", "timestamp", "value"]
              and .offset == $expected_offset
              and (.timestamp | type == "number" and floor == .)
              and .key == $key
              and .value == $value
              and .headers == {($header_key): $header_value}
          )
          and (([.. | objects | has("error")] | any) | not)
      )
    ' >/dev/null
}

request() {
  HTTP_METHOD="$1"
  HTTP_URL="$2"
  EXPECTED_STATUS="$3"
  HTTP_PAYLOAD="${4-}"
  : > "$RESPONSE_FILE"

  if [ -n "$HTTP_PAYLOAD" ]; then
    if ! HTTP_STATUS=$(curl --silent --show-error --fail-with-body \
      --output "$RESPONSE_FILE" --write-out '%{http_code}' \
      --request "$HTTP_METHOD" \
      --header 'Content-Type: application/json' \
      --data "$HTTP_PAYLOAD" \
      "$HTTP_URL"); then
      echo "  x $HTTP_METHOD $HTTP_URL failed"
      cat "$RESPONSE_FILE"
      exit 1
    fi
  elif ! HTTP_STATUS=$(curl --silent --show-error --fail-with-body \
    --output "$RESPONSE_FILE" --write-out '%{http_code}' \
    --request "$HTTP_METHOD" \
    "$HTTP_URL"); then
    echo "  x $HTTP_METHOD $HTTP_URL failed"
    cat "$RESPONSE_FILE"
    exit 1
  fi

  if [ "$HTTP_STATUS" != "$EXPECTED_STATUS" ]; then
    echo "  x $HTTP_METHOD $HTTP_URL returned $HTTP_STATUS; expected $EXPECTED_STATUS"
    cat "$RESPONSE_FILE"
    exit 1
  fi
  RESPONSE=$(cat "$RESPONSE_FILE")
}

main() {
  command -v jq >/dev/null 2>&1 || {
    echo "  x jq is required for structural smoke-test assertions"
    exit 1
  }

  RESPONSE_FILE="${TMPDIR:-/tmp}/streamline-smoke-response.$$"
  trap 'rm -f "$RESPONSE_FILE"' EXIT

  echo "=== Streamline Smoke Test ==="
  echo ""

  echo "[1/6] Waiting for Streamline to be healthy..."
  i=0
  until curl -sf "$STREAMLINE_HTTP_URL/health" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
      echo "  x Streamline did not become healthy within 60s"
      exit 1
    fi
    sleep 1
  done
  echo "  ok Health endpoint responding"

  echo "[2/6] Verifying health response..."
  request GET "$STREAMLINE_HTTP_URL/health" 200
  printf '%s\n' "$RESPONSE" | assert_health_response || {
    echo "  x Health endpoint returned malformed or unhealthy JSON"
    printf '%s\n' "$RESPONSE"
    exit 1
  }
  echo "  ok Health check passed"

  echo "[3/6] Creating test topic '$SMOKE_TOPIC'..."
  request POST "$STREAMLINE_HTTP_URL/api/v1/topics" 201 \
    "{\"name\":\"$SMOKE_TOPIC\",\"partitions\":$SMOKE_PARTITIONS}"
  printf '%s\n' "$RESPONSE" | assert_create_response || {
    echo "  x Topic creation returned an unexpected JSON document"
    printf '%s\n' "$RESPONSE"
    exit 1
  }
  echo "  ok Topic created"

  echo "[4/6] Listing topics..."
  request GET "$STREAMLINE_HTTP_URL/api/v1/topics" 200
  printf '%s\n' "$RESPONSE" | assert_topic_list_response || {
    echo "  x Topic list is malformed or lacks exactly one $SMOKE_TOPIC with $SMOKE_PARTITIONS partitions"
    printf '%s\n' "$RESPONSE"
    exit 1
  }
  echo "  ok Topic listing contains $SMOKE_TOPIC with $SMOKE_PARTITIONS partitions"

  echo "[5/6] Producing test message..."
  request POST "$STREAMLINE_HTTP_URL/api/v1/topics/$SMOKE_TOPIC/messages" 200 \
    "{\"records\":[{\"key\":\"$SMOKE_KEY\",\"value\":\"$SMOKE_VALUE\",\"partition\":0,\"headers\":{\"$SMOKE_HEADER_KEY\":\"$SMOKE_HEADER_VALUE\"}}]}"
  if ! PRODUCED_OFFSET=$(printf '%s\n' "$RESPONSE" | extract_produced_offset); then
    echo "  x Produce returned malformed JSON or an invalid offset"
    printf '%s\n' "$RESPONSE"
    exit 1
  fi
  echo "  ok Message produced at partition 0 offset $PRODUCED_OFFSET"

  echo "[6/6] Consuming messages..."
  request GET "$STREAMLINE_HTTP_URL/api/v1/topics/$SMOKE_TOPIC/partitions/0/messages?offset=$PRODUCED_OFFSET&limit=1" 200
  printf '%s\n' "$RESPONSE" | assert_consume_response "$PRODUCED_OFFSET" || {
    echo "  x Consumed record did not exactly match the produced record"
    printf '%s\n' "$RESPONSE"
    exit 1
  }
  echo "  ok Message consumed and verified"

  echo ""
  echo "=== All smoke tests passed! ==="
}

if [ "${STREAMLINE_SMOKE_LIBRARY_ONLY:-0}" != "1" ]; then
  main "$@"
fi
