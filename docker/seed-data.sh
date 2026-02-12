#!/usr/bin/env bash
set -euo pipefail

HOST="${STREAMLINE_HOST:-localhost}"
KAFKA_PORT="${STREAMLINE_KAFKA_PORT:-9092}"
HTTP_PORT="${STREAMLINE_HTTP_PORT:-9094}"
BASE_URL="http://${HOST}:${HTTP_PORT}"

TOPICS=("demo-events" "demo-logs" "demo-metrics" "demo-orders")
TOTAL_MESSAGES=0

# --- Helpers ---

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

# --- Create Topics ---

create_topics() {
  echo "📦 Creating demo topics..."
  create_topic "demo-events" 2
  create_topic "demo-logs" 1
  create_topic "demo-metrics" 2
  create_topic "demo-orders" 2
  echo "✅ Topics created"
  echo ""
}

# --- Seed: demo-events ---

seed_events() {
  echo "📨 Seeding demo-events (user activity events)..."
  local events=(
    '{"event":"user.signup","user_id":"u-1001","email":"alice@example.com","plan":"free","ts":"2025-01-15T09:00:00Z"}'
    '{"event":"user.login","user_id":"u-1001","ip":"192.168.1.10","ts":"2025-01-15T09:05:00Z"}'
    '{"event":"user.signup","user_id":"u-1002","email":"bob@example.com","plan":"pro","ts":"2025-01-15T09:10:00Z"}'
    '{"event":"page.view","user_id":"u-1001","page":"/dashboard","duration_ms":1200,"ts":"2025-01-15T09:12:00Z"}'
    '{"event":"user.login","user_id":"u-1002","ip":"10.0.0.42","ts":"2025-01-15T09:15:00Z"}'
    '{"event":"feature.used","user_id":"u-1001","feature":"export_csv","ts":"2025-01-15T09:20:00Z"}'
    '{"event":"page.view","user_id":"u-1002","page":"/settings","duration_ms":800,"ts":"2025-01-15T09:22:00Z"}'
    '{"event":"user.upgrade","user_id":"u-1001","from":"free","to":"pro","ts":"2025-01-15T09:30:00Z"}'
    '{"event":"user.signup","user_id":"u-1003","email":"charlie@example.com","plan":"enterprise","ts":"2025-01-15T09:35:00Z"}'
    '{"event":"user.logout","user_id":"u-1002","ts":"2025-01-15T09:40:00Z"}'
  )
  for msg in "${events[@]}"; do
    produce_message "demo-events" "$msg"
  done
  echo "  ✅ ${#events[@]} events produced"
}

# --- Seed: demo-logs ---

seed_logs() {
  echo "📝 Seeding demo-logs (application log lines)..."
  local logs=(
    '{"level":"INFO","service":"api-gateway","msg":"Server started on port 8080","ts":"2025-01-15T09:00:01Z"}'
    '{"level":"INFO","service":"auth-service","msg":"Connected to database","ts":"2025-01-15T09:00:02Z"}'
    '{"level":"WARN","service":"api-gateway","msg":"Rate limit approaching for client 10.0.0.42","ts":"2025-01-15T09:05:30Z"}'
    '{"level":"INFO","service":"order-service","msg":"Processing order ORD-5001","ts":"2025-01-15T09:10:00Z"}'
    '{"level":"ERROR","service":"payment-service","msg":"Payment gateway timeout after 30s","trace_id":"abc-123","ts":"2025-01-15T09:10:05Z"}'
    '{"level":"INFO","service":"payment-service","msg":"Retry succeeded for payment PAY-7890","trace_id":"abc-123","ts":"2025-01-15T09:10:08Z"}'
    '{"level":"DEBUG","service":"cache-service","msg":"Cache hit ratio: 94.2%","ts":"2025-01-15T09:15:00Z"}'
    '{"level":"WARN","service":"auth-service","msg":"Failed login attempt for user unknown@test.com","ts":"2025-01-15T09:20:00Z"}'
    '{"level":"INFO","service":"api-gateway","msg":"Health check passed","ts":"2025-01-15T09:25:00Z"}'
    '{"level":"INFO","service":"order-service","msg":"Order ORD-5001 shipped","ts":"2025-01-15T09:30:00Z"}'
  )
  for msg in "${logs[@]}"; do
    produce_message "demo-logs" "$msg"
  done
  echo "  ✅ ${#logs[@]} log entries produced"
}

# --- Seed: demo-metrics ---

seed_metrics() {
  echo "📊 Seeding demo-metrics (system metrics)..."
  local metrics=(
    '{"metric":"cpu_usage_percent","host":"web-01","value":42.5,"ts":"2025-01-15T09:00:00Z"}'
    '{"metric":"memory_usage_mb","host":"web-01","value":1024,"ts":"2025-01-15T09:00:00Z"}'
    '{"metric":"http_requests_total","host":"web-01","value":15230,"method":"GET","status":200,"ts":"2025-01-15T09:00:00Z"}'
    '{"metric":"cpu_usage_percent","host":"web-02","value":67.8,"ts":"2025-01-15T09:00:00Z"}'
    '{"metric":"disk_usage_percent","host":"db-01","value":71.2,"mount":"/data","ts":"2025-01-15T09:00:00Z"}'
    '{"metric":"http_latency_p99_ms","host":"web-01","value":245,"endpoint":"/api/orders","ts":"2025-01-15T09:05:00Z"}'
    '{"metric":"memory_usage_mb","host":"web-02","value":1820,"ts":"2025-01-15T09:05:00Z"}'
    '{"metric":"connection_pool_active","host":"db-01","value":18,"max":50,"ts":"2025-01-15T09:05:00Z"}'
    '{"metric":"cpu_usage_percent","host":"web-01","value":38.1,"ts":"2025-01-15T09:10:00Z"}'
    '{"metric":"http_requests_total","host":"web-02","value":8920,"method":"POST","status":201,"ts":"2025-01-15T09:10:00Z"}'
  )
  for msg in "${metrics[@]}"; do
    produce_message "demo-metrics" "$msg"
  done
  echo "  ✅ ${#metrics[@]} metrics produced"
}

# --- Seed: demo-orders ---

seed_orders() {
  echo "🛒 Seeding demo-orders (e-commerce order records)..."
  local orders=(
    '{"order_id":"ORD-5001","customer_id":"u-1001","status":"confirmed","items":[{"sku":"WIDGET-A","qty":2,"price":29.99}],"total":59.98,"ts":"2025-01-15T09:10:00Z"}'
    '{"order_id":"ORD-5002","customer_id":"u-1002","status":"confirmed","items":[{"sku":"GADGET-B","qty":1,"price":149.00},{"sku":"CABLE-C","qty":3,"price":9.99}],"total":178.97,"ts":"2025-01-15T09:12:00Z"}'
    '{"order_id":"ORD-5001","customer_id":"u-1001","status":"processing","ts":"2025-01-15T09:15:00Z"}'
    '{"order_id":"ORD-5003","customer_id":"u-1003","status":"confirmed","items":[{"sku":"WIDGET-A","qty":10,"price":29.99}],"total":299.90,"ts":"2025-01-15T09:18:00Z"}'
    '{"order_id":"ORD-5002","customer_id":"u-1002","status":"processing","ts":"2025-01-15T09:20:00Z"}'
    '{"order_id":"ORD-5001","customer_id":"u-1001","status":"shipped","carrier":"FastShip","tracking":"FS-98765","ts":"2025-01-15T09:25:00Z"}'
    '{"order_id":"ORD-5004","customer_id":"u-1001","status":"confirmed","items":[{"sku":"PREMIUM-D","qty":1,"price":499.00}],"total":499.00,"ts":"2025-01-15T09:28:00Z"}'
    '{"order_id":"ORD-5002","customer_id":"u-1002","status":"shipped","carrier":"QuickPost","tracking":"QP-12345","ts":"2025-01-15T09:30:00Z"}'
    '{"order_id":"ORD-5003","customer_id":"u-1003","status":"processing","ts":"2025-01-15T09:32:00Z"}'
    '{"order_id":"ORD-5001","customer_id":"u-1001","status":"delivered","ts":"2025-01-15T09:45:00Z"}'
  )
  for msg in "${orders[@]}"; do
    produce_message "demo-orders" "$msg"
  done
  echo "  ✅ ${#orders[@]} order records produced"
}

# --- Main ---

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     Streamline Demo Data Seeder              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

wait_for_server
create_topics

echo "🌱 Seeding sample data..."
echo ""
seed_events
seed_logs
seed_metrics
seed_orders

echo ""
echo "══════════════════════════════════════════════"
echo "✅ Seeding complete!"
echo ""
echo "  Topics created:  ${#TOPICS[@]}"
echo "  Messages seeded: ${TOTAL_MESSAGES}"
echo ""
echo "  Topics:"
for t in "${TOPICS[@]}"; do
  echo "    • ${t}"
done
echo ""
echo "  Try consuming:"
echo "    streamline-cli --broker localhost:9092 consume demo-events --from-beginning -n 5"
echo "══════════════════════════════════════════════"
echo ""
