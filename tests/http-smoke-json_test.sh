#!/usr/bin/env bash
# Regression tests for the exact JSON predicates used by the release smoke test.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STREAMLINE_SMOKE_LIBRARY_ONLY=1
export STREAMLINE_SMOKE_LIBRARY_ONLY
# shellcheck source=../docker/smoke-test.sh
source "$REPO_ROOT/docker/smoke-test.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

rejects() {
  local validator="$1"
  local fixture="$2"
  shift 2
  if printf '%s\n' "$fixture" | "$validator" "$@" 2>/dev/null; then
    fail "$validator accepted invalid fixture: $fixture"
  fi
}

valid_health='{"status":"healthy","checks":[{"name":"storage","status":"ok"},{"name":"data_directory","status":"ok"}]}'
printf '%s\n' "$valid_health" | assert_health_response \
  || fail "valid health response was rejected"
rejects assert_health_response \
  '{"status":"healthy","checks":[{"name":"storage","status":"ok"}],"error":"hidden failure"}'
rejects assert_health_response \
  '{"status":"healthy","checks":[{"name":"storage","status":"ok","error":"degraded"}]}'
rejects assert_health_response '{"status":"healthy"}'
rejects assert_health_response "$valid_health
$valid_health"

partition_zero='{"partition_id":0,"leader":1,"replicas":[1],"isr":[1],"start_offset":0,"end_offset":0,"size_bytes":0}'
partition_one='{"partition_id":1,"leader":1,"replicas":[1],"isr":[1],"start_offset":0,"end_offset":0,"size_bytes":0}'
valid_create="{\"name\":\"smoke-test\",\"partition_count\":2,\"replication_factor\":1,\"is_internal\":false,\"partitions\":[$partition_zero,$partition_one],\"config\":{\"cleanup.policy\":\"delete\"},\"total_messages\":0,\"total_bytes\":128,\"messages_per_second\":0.0,\"bytes_per_second\":0.0}"
printf '%s\n' "$valid_create" | assert_create_response \
  || fail "valid topic-create response was rejected"
rejects assert_create_response \
  '{"name":"smoke-test","partition_count":2,"error":"create failed"}'
rejects assert_create_response \
  "{\"name\":\"smoke-test\",\"partition_count\":2,\"replication_factor\":1,\"is_internal\":false,\"partitions\":[{\"partition_id\":0,\"leader\":1,\"replicas\":[1],\"isr\":[1],\"start_offset\":0,\"end_offset\":0,\"size_bytes\":0,\"error\":\"bad partition\"},$partition_one],\"config\":{},\"total_messages\":0,\"total_bytes\":128,\"messages_per_second\":0.0,\"bytes_per_second\":0.0}"
rejects assert_create_response \
  '{"name":"smoke-test","partition_count":2,"replication_factor":1}'
rejects assert_create_response \
  "{\"name\":\"smoke-test\",\"partition_count\":2,\"replication_factor\":1,\"is_internal\":false,\"partitions\":[$partition_zero,true],\"config\":{},\"total_messages\":0,\"total_bytes\":128,\"messages_per_second\":0.0,\"bytes_per_second\":0.0}"
rejects assert_create_response \
  "{\"name\":\"smoke-test\",\"partition_count\":2,\"replication_factor\":1,\"is_internal\":false,\"partitions\":[$partition_zero,$partition_zero],\"config\":{},\"total_messages\":0,\"total_bytes\":128,\"messages_per_second\":0.0,\"bytes_per_second\":0.0}"
rejects assert_create_response \
  "{\"name\":\"smoke-test\",\"partition_count\":2,\"replication_factor\":1,\"is_internal\":false,\"partitions\":[$partition_zero,$partition_one],\"config\":{\"cleanup.policy\":true},\"total_messages\":0,\"total_bytes\":128,\"messages_per_second\":0.0,\"bytes_per_second\":0.0}"
rejects assert_create_response "[$valid_create]"
rejects assert_create_response "$valid_create
$valid_create"

valid_topic='{"name":"smoke-test","partition_count":2,"replication_factor":1,"is_internal":false,"total_messages":0,"total_bytes":128}'
printf '%s\n' \
  "[$valid_topic,{\"name\":\"other\",\"partition_count\":1,\"replication_factor\":1,\"is_internal\":false,\"total_messages\":0,\"total_bytes\":0}]" \
  | assert_topic_list_response \
  || fail "valid topic-list response was rejected"
rejects assert_topic_list_response \
  '{"error":"backend failed","name":"smoke-test","partition_count":2}'
rejects assert_topic_list_response \
  '[{"name":"smoke-test","partition_count":2,"replication_factor":1,"is_internal":false,"total_messages":0,"total_bytes":128,"error":"hidden"}]'
rejects assert_topic_list_response '{"name":"smoke-test"'
rejects assert_topic_list_response \
  '[{"name":"smoke-test","partition_count":2,"replication_factor":1,"is_internal":false,"total_messages":0}]'
rejects assert_topic_list_response "[$valid_topic]
[$valid_topic]"

valid_produce='{"offsets":[{"partition":0,"offset":7}]}'
offset="$(
  printf '%s\n' "$valid_produce" \
    | extract_produced_offset
)"
[ "$offset" = "7" ] || fail "valid produce offset was not extracted"
rejects extract_produced_offset \
  '{"error":"produce failed","offsets":[{"partition":0,"offset":7}]}'
rejects extract_produced_offset \
  '{"offsets":[{"partition":0,"offset":7,"error":"hidden"}]}'
rejects extract_produced_offset '{"offsets":[{"partition":0}]}'
rejects extract_produced_offset '{"offsets":['
rejects extract_produced_offset "$valid_produce
$valid_produce"

valid_consume='{"topic":"smoke-test","partition":0,"records":[{"offset":7,"timestamp":1700000000000,"key":"smoke-key","value":"streamline-http-smoke-payload-v1","headers":{"smoke-test":"true"}}],"next_offset":8}'
printf '%s\n' "$valid_consume" | assert_consume_response 7 \
  || fail "valid consume response was rejected"
rejects assert_consume_response \
  '{"error":"read failed","topic":"smoke-test","partition":0,"records":[{"offset":7,"timestamp":1700000000000,"key":"smoke-key","value":"streamline-http-smoke-payload-v1","headers":{"smoke-test":"true"}}],"next_offset":8}' \
  7
rejects assert_consume_response \
  '{"topic":"smoke-test","partition":0,"records":[{"offset":7,"timestamp":1700000000000,"key":"smoke-key","value":"streamline-http-smoke-payload-v1","headers":{"smoke-test":"true"},"error":"hidden"}],"next_offset":8}' \
  7
rejects assert_consume_response \
  '{"topic":"smoke-test","partition":0,"records":[{"offset":7,"key":"smoke-key","value":"streamline-http-smoke-payload-v1","headers":{"smoke-test":"true"}}],"next_offset":8}' \
  7
rejects assert_consume_response '{"records":[' 7
rejects assert_consume_response "$valid_consume
$valid_consume" 7

echo "HTTP smoke JSON validation passed"
