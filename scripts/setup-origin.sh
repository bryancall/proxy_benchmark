#!/bin/bash
# setup-origin.sh - Setup origin host (runs nginx backend)
# Run this on the machine configured as hosts.origin in benchmark.yaml

set -e

echo "=== Setting up origin host ==="

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
    nginx \
    yq \
    bc

# Verify installations
echo ""
echo "=== Verifying installations ==="

echo -n "nginx: "
nginx -v 2>&1 || echo "FAILED"

echo -n "yq: "
yq --version || echo "FAILED"

# Stop default nginx service (we'll run with custom config)
echo ""
echo "=== Stopping default nginx service ==="
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true

echo ""
echo "=== Origin host setup complete ==="
echo "Next steps:"
echo "  1. Run ./scripts/generate-content.sh to create test content"
echo "  2. Start origin server: nginx -c \$(pwd)/backend/nginx.conf"

