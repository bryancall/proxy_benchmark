#!/bin/bash
# generate-certs.sh - Generate self-signed TLS certificates for benchmarking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_DIR="${PROJECT_DIR}/certs"
CONFIG_FILE="${PROJECT_DIR}/benchmark.yaml"

# Read proxy host from config
if [ -f "$CONFIG_FILE" ] && command -v yq &> /dev/null; then
    PROXY_HOST=$(yq '.hosts.proxy' "$CONFIG_FILE")
else
    PROXY_HOST="localhost"
fi

echo "=== Generating TLS certificates ==="
echo "Proxy host: ${PROXY_HOST}"
echo "Output directory: ${CERT_DIR}"

mkdir -p "$CERT_DIR"

# Generate CA key and certificate
echo ""
echo "Generating CA certificate..."
openssl genrsa -out "${CERT_DIR}/ca.key" 4096

openssl req -new -x509 -days 3650 -key "${CERT_DIR}/ca.key" \
    -out "${CERT_DIR}/ca.crt" \
    -subj "/C=US/ST=California/L=San Francisco/O=Proxy Benchmark/CN=Benchmark CA"

# Generate server key
echo ""
echo "Generating server certificate..."
openssl genrsa -out "${CERT_DIR}/server.key" 2048

# Create CSR config with SAN
cat > "${CERT_DIR}/server.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
ST = California
L = San Francisco
O = Proxy Benchmark
CN = ${PROXY_HOST}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${PROXY_HOST}
DNS.2 = localhost
DNS.3 = *.local
IP.1 = 127.0.0.1
EOF

# Generate CSR
openssl req -new -key "${CERT_DIR}/server.key" \
    -out "${CERT_DIR}/server.csr" \
    -config "${CERT_DIR}/server.cnf"

# Create extensions file for signing
cat > "${CERT_DIR}/server_ext.cnf" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${PROXY_HOST}
DNS.2 = localhost
DNS.3 = *.local
IP.1 = 127.0.0.1
EOF

# Sign server certificate with CA
openssl x509 -req -in "${CERT_DIR}/server.csr" \
    -CA "${CERT_DIR}/ca.crt" \
    -CAkey "${CERT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CERT_DIR}/server.crt" \
    -days 365 \
    -extfile "${CERT_DIR}/server_ext.cnf"

# Create combined PEM file (for some proxies)
cat "${CERT_DIR}/server.crt" "${CERT_DIR}/server.key" > "${CERT_DIR}/server.pem"

# Clean up temp files
rm -f "${CERT_DIR}/server.csr" "${CERT_DIR}/server.cnf" "${CERT_DIR}/server_ext.cnf" "${CERT_DIR}/ca.srl"

echo ""
echo "=== Certificates generated ==="
echo "  CA Certificate:     ${CERT_DIR}/ca.crt"
echo "  Server Certificate: ${CERT_DIR}/server.crt"
echo "  Server Key:         ${CERT_DIR}/server.key"
echo "  Combined PEM:       ${CERT_DIR}/server.pem"
echo ""
echo "For h2load to trust the certificate, use: --ca-cert=${CERT_DIR}/ca.crt"

