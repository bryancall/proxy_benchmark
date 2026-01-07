#!/bin/bash
# setup-proxy.sh - Setup proxy host (runs ATS, Nginx, Envoy, HAProxy)
# Run this on the machine configured as hosts.proxy in benchmark.yaml

set -e

echo "=== Setting up proxy host ==="

# Check if running on Fedora
if [ -f /etc/fedora-release ]; then
    echo "Detected Fedora, using dnf..."
    PKG_MGR="dnf"
else
    echo "Warning: This script is designed for Fedora. Adjust package manager as needed."
    PKG_MGR="dnf"
fi

echo "Installing required packages..."
sudo $PKG_MGR install -y \
    yq \
    trafficserver \
    nginx \
    envoy \
    haproxy \
    sysstat \
    ethtool \
    bc

# Verify installations
echo ""
echo "=== Verifying installations ==="

echo -n "yq: "
yq --version || echo "FAILED"

echo -n "trafficserver: "
traffic_server --version 2>&1 | head -1 || echo "FAILED"

echo -n "nginx: "
nginx -v 2>&1 || echo "FAILED"

echo -n "envoy: "
envoy --version 2>&1 | head -1 || echo "FAILED"

echo -n "haproxy: "
haproxy -v | head -1 || echo "FAILED"

echo -n "pidstat: "
pidstat -V 2>&1 | head -1 || echo "FAILED"

echo -n "sar: "
sar -V 2>&1 | head -1 || echo "FAILED"

# Stop any running services (we'll manage them manually during benchmarks)
echo ""
echo "=== Stopping default services ==="
sudo systemctl stop trafficserver 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop envoy 2>/dev/null || true
sudo systemctl stop haproxy 2>/dev/null || true

sudo systemctl disable trafficserver 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true
sudo systemctl disable envoy 2>/dev/null || true
sudo systemctl disable haproxy 2>/dev/null || true

echo ""
echo "=== Proxy host setup complete ==="
echo "Proxy services have been stopped and disabled."
echo "The benchmark script will start them as needed."

