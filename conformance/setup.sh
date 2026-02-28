#!/usr/bin/env bash
# Setup script for conformance test environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"

echo "=== Streamline SDK Conformance Test Setup ==="

# Generate self-signed certificates
mkdir -p "$CERTS_DIR"
if [ ! -f "${CERTS_DIR}/ca.key" ]; then
    echo "[1/4] Generating CA certificate..."
    openssl req -new -x509 -days 365 -nodes \
        -keyout "${CERTS_DIR}/ca.key" \
        -out "${CERTS_DIR}/ca.crt" \
        -subj "/CN=Streamline Conformance CA"

    echo "[2/4] Generating server certificate..."
    openssl req -new -nodes \
        -keyout "${CERTS_DIR}/server.key" \
        -out "${CERTS_DIR}/server.csr" \
        -subj "/CN=localhost"
    
    openssl x509 -req -days 365 \
        -in "${CERTS_DIR}/server.csr" \
        -CA "${CERTS_DIR}/ca.crt" \
        -CAkey "${CERTS_DIR}/ca.key" \
        -CAcreateserial \
        -out "${CERTS_DIR}/server.crt" \
        -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")

    echo "[3/4] Generating client certificate..."
    openssl req -new -nodes \
        -keyout "${CERTS_DIR}/client.key" \
        -out "${CERTS_DIR}/client.csr" \
        -subj "/CN=conformance-client"
    
    openssl x509 -req -days 365 \
        -in "${CERTS_DIR}/client.csr" \
        -CA "${CERTS_DIR}/ca.crt" \
        -CAkey "${CERTS_DIR}/ca.key" \
        -CAcreateserial \
        -out "${CERTS_DIR}/client.crt"

    rm -f "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.srl
    echo "[4/4] Certificates generated in ${CERTS_DIR}"
else
    echo "Certificates already exist. Skipping generation."
fi

# Start conformance server
echo ""
echo "Starting conformance server..."
docker compose -f "${SCRIPT_DIR}/../docker-compose.conformance.yml" up -d

echo ""
echo "Waiting for server to be healthy..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:19094/health > /dev/null 2>&1; then
        echo "Server is healthy!"
        break
    fi
    sleep 1
done

# Create conformance topics
echo ""
echo "Creating conformance topics..."
for i in $(seq 1 10); do
    curl -sf -X POST http://localhost:19094/api/topics \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"conformance-${i}\", \"partitions\": 3, \"replication_factor\": 1}" \
        > /dev/null 2>&1 || true
    echo "  Created: conformance-${i}"
done

echo ""
echo "=== Conformance environment ready ==="
echo "  Kafka protocol: localhost:19092"
echo "  HTTP API:       localhost:19094"
echo "  TLS endpoint:   localhost:19192"
echo "  Users:          admin/admin-secret, alice/alice-secret, bob/bob-secret"
