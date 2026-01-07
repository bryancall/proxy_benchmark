#!/bin/bash
# start-proxy.sh - Start a proxy server for benchmarking
# Usage: ./start-proxy.sh <proxy_name>
#   proxy_name: ats, nginx, envoy, haproxy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/benchmark.yaml"
CERT_DIR="${PROJECT_DIR}/certs"

PROXY="${1:?Usage: $0 <proxy_name> (ats, nginx, envoy, haproxy)}"

# Read config
ORIGIN_HOST=$(yq '.hosts.origin' "$CONFIG_FILE")
ORIGIN_PORT=$(yq '.ports.origin' "$CONFIG_FILE")

echo "=== Starting ${PROXY} ==="
echo "Origin: ${ORIGIN_HOST}:${ORIGIN_PORT}"

case "$PROXY" in
    nginx)
        HTTP_PORT=$(yq '.ports.proxies.nginx.http' "$CONFIG_FILE")
        HTTPS_PORT=$(yq '.ports.proxies.nginx.https' "$CONFIG_FILE")
        
        # Generate config from template
        CONFIG="/tmp/nginx-proxy.conf"
        sed -e "s/{{ORIGIN_HOST}}/${ORIGIN_HOST}/g" \
            -e "s/{{ORIGIN_PORT}}/${ORIGIN_PORT}/g" \
            -e "s|{{CERT_DIR}}|${CERT_DIR}|g" \
            "${PROJECT_DIR}/configs/nginx/nginx.conf" > "$CONFIG"
        
        echo "Starting nginx on HTTP:${HTTP_PORT} HTTPS:${HTTPS_PORT}"
        nginx -c "$CONFIG"
        echo "nginx started (PID in /tmp/nginx-proxy.pid)"
        ;;
        
    ats)
        echo "ATS requires more setup - use trafficserver directly"
        echo "TODO: Add ATS startup script"
        exit 1
        ;;
        
    envoy)
        HTTP_PORT=$(yq '.ports.proxies.envoy.http' "$CONFIG_FILE")
        HTTPS_PORT=$(yq '.ports.proxies.envoy.https' "$CONFIG_FILE")
        
        # Generate config from template
        CONFIG="/tmp/envoy.yaml"
        sed -e "s/{{ORIGIN_HOST}}/${ORIGIN_HOST}/g" \
            -e "s/{{ORIGIN_PORT}}/${ORIGIN_PORT}/g" \
            -e "s|{{CERT_DIR}}|${CERT_DIR}|g" \
            "${PROJECT_DIR}/configs/envoy/envoy.yaml" > "$CONFIG"
        
        echo "Starting envoy on HTTP:${HTTP_PORT} HTTPS:${HTTPS_PORT}"
        envoy -c "$CONFIG" --log-path /tmp/envoy.log &
        echo $! > /tmp/envoy.pid
        echo "envoy started (PID: $(cat /tmp/envoy.pid))"
        ;;
        
    haproxy)
        HTTP_PORT=$(yq '.ports.proxies.haproxy.http' "$CONFIG_FILE")
        HTTPS_PORT=$(yq '.ports.proxies.haproxy.https' "$CONFIG_FILE")
        
        # Generate config from template
        CONFIG="/tmp/haproxy.cfg"
        sed -e "s/{{ORIGIN_HOST}}/${ORIGIN_HOST}/g" \
            -e "s/{{ORIGIN_PORT}}/${ORIGIN_PORT}/g" \
            -e "s|{{CERT_DIR}}|${CERT_DIR}|g" \
            "${PROJECT_DIR}/configs/haproxy/haproxy.cfg" > "$CONFIG"
        
        echo "Starting haproxy on HTTP:${HTTP_PORT} HTTPS:${HTTPS_PORT}"
        haproxy -f "$CONFIG" -D -p /tmp/haproxy.pid
        echo "haproxy started (PID in /tmp/haproxy.pid)"
        ;;
        
    *)
        echo "Unknown proxy: $PROXY"
        echo "Supported: ats, nginx, envoy, haproxy"
        exit 1
        ;;
esac

sleep 1
echo "=== ${PROXY} started ==="

