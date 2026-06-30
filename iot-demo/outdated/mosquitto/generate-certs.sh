#!/usr/bin/env bash
# Generates a self-signed CA and a server cert for local MQTTS.
# Run once from the repo root: bash mosquitto/generate-certs.sh
set -euo pipefail

CERT_DIR="$(dirname "$0")/certs"
mkdir -p "$CERT_DIR"

# CA
openssl genrsa -out "$CERT_DIR/ca.key" 2048
openssl req -new -x509 -days 3650 -key "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.crt" -subj "/CN=local-mqtt-ca"

# Server cert signed by the CA, valid for both the Docker service name and localhost
cat > "$CERT_DIR/san.cnf" << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = DNS:mosquitto,DNS:localhost,IP:127.0.0.1
EOF

openssl genrsa -out "$CERT_DIR/server.key" 2048
openssl req -new -key "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.csr" -subj "/CN=mosquitto" \
  -config "$CERT_DIR/san.cnf"
openssl x509 -req -days 3650 \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
  -out "$CERT_DIR/server.crt" \
  -extensions v3_req -extfile "$CERT_DIR/san.cnf"

rm "$CERT_DIR/server.csr" "$CERT_DIR/san.cnf"
echo "Certs written to $CERT_DIR"
