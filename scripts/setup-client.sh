#!/bin/bash
# setup-client.sh - Setup client host (runs h2load)
# Run this on the machine configured as hosts.client in benchmark.yaml

set -e

echo "=== Setting up client host ==="

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
    nghttp2 \
    sysstat \
    ethtool \
    bc

# Verify installations
echo ""
echo "=== Verifying installations ==="

echo -n "yq: "
yq --version || echo "FAILED"

echo -n "h2load: "
h2load --version | head -1 || echo "FAILED"

echo -n "pidstat: "
pidstat -V 2>&1 | head -1 || echo "FAILED"

echo -n "sar: "
sar -V 2>&1 | head -1 || echo "FAILED"

echo -n "ethtool: "
ethtool --version || echo "FAILED"

echo ""
echo "=== Client host setup complete ==="
echo "You can now run benchmarks from this host."

