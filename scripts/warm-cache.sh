#!/bin/bash
# warm-cache.sh - Warm proxy cache before benchmark
# Usage: ./warm-cache.sh <proxy> <protocol> <port>
#   proxy: ats, nginx, envoy, haproxy
#   protocol: http1-plain, http1-tls, http2-tls
#   port: proxy port to use

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/benchmark.yaml"
CERT_DIR="${PROJECT_DIR}/certs"

# Arguments
PROXY="${1:-ats}"
PROTOCOL="${2:-http2-tls}"
PORT="${3:-8443}"

# Read configuration
PROXY_HOST=$(yq '.hosts.proxy' "$CONFIG_FILE")
WARMUP_DURATION=$(yq '.cache.warmup_duration' "$CONFIG_FILE")
WARMUP_URLS=$(yq '.cache.warmup_urls' "$CONFIG_FILE")

echo "=== Warming cache ==="
echo "Proxy: ${PROXY} on ${PROXY_HOST}:${PORT}"
echo "Protocol: ${PROTOCOL}"
echo "Duration: ${WARMUP_DURATION}s"
echo "URLs: ${WARMUP_URLS}"

# Determine URL scheme and h2load options
case "$PROTOCOL" in
    http1-plain)
        SCHEME="http"
        H2LOAD_OPTS="--h1"
        ;;
    http1-tls)
        SCHEME="https"
        H2LOAD_OPTS="--h1"
        ;;
    http2-tls)
        SCHEME="https"
        H2LOAD_OPTS=""
        ;;
    *)
        echo "Unknown protocol: $PROTOCOL"
        exit 1
        ;;
esac

# Generate URL list file
URL_FILE=$(mktemp)
trap "rm -f $URL_FILE" EXIT

for i in $(seq 1 "$WARMUP_URLS"); do
    echo "${SCHEME}://${PROXY_HOST}:${PORT}/cacheable/${i}" >> "$URL_FILE"
done

echo ""
echo "Warming cache with ${WARMUP_URLS} URLs for ${WARMUP_DURATION} seconds..."

# Build h2load command
H2LOAD_CMD="h2load"
H2LOAD_CMD+=" -D ${WARMUP_DURATION}"
H2LOAD_CMD+=" -c 100"
H2LOAD_CMD+=" -t 4"
H2LOAD_CMD+=" ${H2LOAD_OPTS}"

# Add TLS options if needed
if [[ "$SCHEME" == "https" ]]; then
    if [ -f "${CERT_DIR}/ca.crt" ]; then
        # Use our CA cert for verification
        H2LOAD_CMD+=" --ca-cert=${CERT_DIR}/ca.crt"
    else
        # Fall back to insecure if no CA cert
        H2LOAD_CMD+=" --insecure"
    fi
fi

# Add URL file
H2LOAD_CMD+=" -i ${URL_FILE}"

# Run warmup
echo "Running: ${H2LOAD_CMD}"
eval "$H2LOAD_CMD" 2>&1 | tail -20

echo ""
echo "=== Cache warming complete ==="

