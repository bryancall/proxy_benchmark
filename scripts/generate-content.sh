#!/bin/bash
# generate-content.sh - Generate test content files for benchmarking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONTENT_DIR="${PROJECT_DIR}/backend/content"
CONFIG_FILE="${PROJECT_DIR}/benchmark.yaml"

# Read configuration
if [ -f "$CONFIG_FILE" ] && command -v yq &> /dev/null; then
    SIZE_KB=$(yq '.response.size_kb' "$CONFIG_FILE")
    NUM_URLS=$(yq '.cache.warmup_urls' "$CONFIG_FILE")
else
    SIZE_KB=1
    NUM_URLS=100
fi

SIZE_BYTES=$((SIZE_KB * 1024))

echo "=== Generating test content ==="
echo "Response size: ${SIZE_KB}KB (${SIZE_BYTES} bytes)"
echo "Number of URLs: ${NUM_URLS}"
echo "Output directory: ${CONTENT_DIR}"

# Create directories
mkdir -p "${CONTENT_DIR}/cacheable"
mkdir -p "${CONTENT_DIR}/uncacheable"

# Generate random content files
echo ""
echo "Generating ${NUM_URLS} cacheable files..."
for i in $(seq 1 "$NUM_URLS"); do
    # Generate random content of specified size
    dd if=/dev/urandom bs="$SIZE_BYTES" count=1 2>/dev/null > "${CONTENT_DIR}/cacheable/${i}"
done

echo "Generating ${NUM_URLS} uncacheable files..."
for i in $(seq 1 "$NUM_URLS"); do
    # Use same content as cacheable (content doesn't affect caching, headers do)
    cp "${CONTENT_DIR}/cacheable/${i}" "${CONTENT_DIR}/uncacheable/${i}"
done

# Show summary
TOTAL_SIZE_MB=$(echo "scale=2; ($SIZE_BYTES * $NUM_URLS * 2) / 1024 / 1024" | bc)
echo ""
echo "=== Content generation complete ==="
echo "  Cacheable files: ${CONTENT_DIR}/cacheable/1 to ${NUM_URLS}"
echo "  Uncacheable files: ${CONTENT_DIR}/uncacheable/1 to ${NUM_URLS}"
echo "  Total size: ~${TOTAL_SIZE_MB}MB"
echo ""
echo "The backend nginx config will serve these with appropriate Cache-Control headers."

