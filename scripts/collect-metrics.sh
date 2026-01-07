#!/bin/bash
# collect-metrics.sh - Collect system metrics during benchmark
# Run this on the proxy host while benchmarks are running
#
# Usage: ./collect-metrics.sh <pid> <duration> <output_prefix>
#   pid: Process ID of the proxy to monitor
#   duration: How long to collect (seconds)
#   output_prefix: Prefix for output files

set -e

PID="${1:?Usage: $0 <pid> <duration> <output_prefix>}"
DURATION="${2:-30}"
OUTPUT_PREFIX="${3:-metrics}"

# Validate PID exists
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Error: Process $PID not found"
    exit 1
fi

echo "=== Collecting metrics ==="
echo "PID: ${PID}"
echo "Duration: ${DURATION}s"
echo "Output prefix: ${OUTPUT_PREFIX}"

# Get process name
PROC_NAME=$(ps -p "$PID" -o comm= 2>/dev/null || echo "unknown")
echo "Process: ${PROC_NAME}"

# Determine network interface (first non-loopback)
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
echo "Network interface: ${NET_IFACE}"

# Create temp directory for raw output
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo ""
echo "Starting metric collection for ${DURATION} seconds..."

# Start pidstat for CPU and memory (sample every second)
pidstat -p "$PID" -r -u 1 "$DURATION" > "${TEMP_DIR}/pidstat.txt" 2>&1 &
PIDSTAT_PID=$!

# Start sar for network statistics (sample every second)
sar -n DEV 1 "$DURATION" > "${TEMP_DIR}/sar_net.txt" 2>&1 &
SAR_PID=$!

# Wait for collection to complete
wait $PIDSTAT_PID 2>/dev/null || true
wait $SAR_PID 2>/dev/null || true

echo "Collection complete. Parsing results..."

# Parse pidstat output
CPU_AVG=$(grep -v "^$\|^Linux\|^#\|Average" "${TEMP_DIR}/pidstat.txt" | \
    grep "$PID" | awk '{sum += $8; count++} END {if (count > 0) print sum/count; else print 0}')

MEM_RSS_AVG=$(grep -v "^$\|^Linux\|^#\|Average" "${TEMP_DIR}/pidstat.txt" | \
    grep "$PID" | awk '{sum += $7; count++} END {if (count > 0) print sum/count; else print 0}')

MEM_RSS_MAX=$(grep -v "^$\|^Linux\|^#\|Average" "${TEMP_DIR}/pidstat.txt" | \
    grep "$PID" | awk 'BEGIN {max=0} {if ($7 > max) max=$7} END {print max}')

# Parse sar network output (get average for the interface)
NET_RX_KB=$(grep "Average.*${NET_IFACE}" "${TEMP_DIR}/sar_net.txt" | awk '{print $5}' || echo "0")
NET_TX_KB=$(grep "Average.*${NET_IFACE}" "${TEMP_DIR}/sar_net.txt" | awk '{print $6}' || echo "0")
NET_RX_PKT=$(grep "Average.*${NET_IFACE}" "${TEMP_DIR}/sar_net.txt" | awk '{print $3}' || echo "0")
NET_TX_PKT=$(grep "Average.*${NET_IFACE}" "${TEMP_DIR}/sar_net.txt" | awk '{print $4}' || echo "0")

# Convert KB/s to MB/s
NET_RX_MB=$(echo "scale=2; ${NET_RX_KB:-0} / 1024" | bc)
NET_TX_MB=$(echo "scale=2; ${NET_TX_KB:-0} / 1024" | bc)

# Generate JSON output
cat > "${OUTPUT_PREFIX}.json" << EOF
{
  "pid": ${PID},
  "process": "${PROC_NAME}",
  "duration": ${DURATION},
  "timestamp": "$(date -Iseconds)",
  "cpu": {
    "percent_avg": ${CPU_AVG:-0}
  },
  "memory": {
    "rss_kb_avg": ${MEM_RSS_AVG:-0},
    "rss_kb_max": ${MEM_RSS_MAX:-0},
    "rss_mb_avg": $(echo "scale=2; ${MEM_RSS_AVG:-0} / 1024" | bc),
    "rss_mb_max": $(echo "scale=2; ${MEM_RSS_MAX:-0} / 1024" | bc)
  },
  "network": {
    "interface": "${NET_IFACE}",
    "rx_mbps": ${NET_RX_MB},
    "tx_mbps": ${NET_TX_MB},
    "rx_pps": ${NET_RX_PKT:-0},
    "tx_pps": ${NET_TX_PKT:-0}
  }
}
EOF

# Also save raw data
cp "${TEMP_DIR}/pidstat.txt" "${OUTPUT_PREFIX}_pidstat.txt"
cp "${TEMP_DIR}/sar_net.txt" "${OUTPUT_PREFIX}_sar.txt"

echo ""
echo "=== Metrics Summary ==="
echo "CPU Average: ${CPU_AVG}%"
echo "Memory RSS Avg: ${MEM_RSS_AVG} KB ($(echo "scale=2; ${MEM_RSS_AVG:-0} / 1024" | bc) MB)"
echo "Memory RSS Max: ${MEM_RSS_MAX} KB ($(echo "scale=2; ${MEM_RSS_MAX:-0} / 1024" | bc) MB)"
echo "Network RX: ${NET_RX_MB} MB/s"
echo "Network TX: ${NET_TX_MB} MB/s"
echo ""
echo "Output files:"
echo "  ${OUTPUT_PREFIX}.json"
echo "  ${OUTPUT_PREFIX}_pidstat.txt"
echo "  ${OUTPUT_PREFIX}_sar.txt"

