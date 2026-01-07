#!/bin/bash
# collect-specs.sh - Gather hardware specifications and save as JSON

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME=$(hostname -s)
OUTPUT_FILE="${SCRIPT_DIR}/${HOSTNAME}.json"

echo "Collecting hardware specs for ${HOSTNAME}..."

# Get CPU info
CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[[:space:]]*//')
CPU_CORES=$(lscpu | grep "^Core(s) per socket" | awk '{print $NF}')
CPU_SOCKETS=$(lscpu | grep "^Socket(s)" | awk '{print $NF}')
CPU_THREADS_PER_CORE=$(lscpu | grep "^Thread(s) per core" | awk '{print $NF}')
CPU_TOTAL_CORES=$((CPU_CORES * CPU_SOCKETS))
CPU_TOTAL_THREADS=$((CPU_TOTAL_CORES * CPU_THREADS_PER_CORE))
CPU_MHZ=$(lscpu | grep "CPU max MHz" | awk '{print $NF}' | cut -d. -f1)
if [ -z "$CPU_MHZ" ]; then
    CPU_MHZ=$(lscpu | grep "CPU MHz" | awk '{print $NF}' | cut -d. -f1)
fi

# Get memory info
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_TOTAL_GB=$(echo "scale=1; $MEM_TOTAL_KB / 1024 / 1024" | bc)

# Try to get memory type and speed (requires root for dmidecode)
MEM_TYPE="unknown"
MEM_SPEED="unknown"
if command -v dmidecode &> /dev/null && [ "$(id -u)" -eq 0 ]; then
    MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep "Type:" | grep -v "Error" | head -1 | awk '{print $2}')
    MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep "Speed:" | grep -v "Unknown" | head -1 | awk '{print $2}')
fi

# Get network interface info
# Find the first non-loopback interface
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
NET_SPEED="unknown"
NET_DRIVER="unknown"
if [ -n "$NET_IFACE" ]; then
    if command -v ethtool &> /dev/null; then
        NET_SPEED=$(ethtool "$NET_IFACE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "unknown")
        NET_DRIVER=$(ethtool -i "$NET_IFACE" 2>/dev/null | grep "driver:" | awk '{print $2}' || echo "unknown")
    fi
fi

# Get kernel version
KERNEL=$(uname -r)

# Get timestamp
TIMESTAMP=$(date -Iseconds)

# Generate JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "hostname": "${HOSTNAME}",
  "timestamp": "${TIMESTAMP}",
  "cpu": {
    "model": "${CPU_MODEL}",
    "cores": ${CPU_TOTAL_CORES},
    "threads": ${CPU_TOTAL_THREADS},
    "base_mhz": ${CPU_MHZ:-0}
  },
  "memory": {
    "total_gb": ${MEM_TOTAL_GB},
    "type": "${MEM_TYPE}",
    "speed_mhz": "${MEM_SPEED}"
  },
  "network": {
    "interface": "${NET_IFACE}",
    "speed": "${NET_SPEED}",
    "driver": "${NET_DRIVER}"
  },
  "kernel": "${KERNEL}"
}
EOF

echo "Hardware specs saved to ${OUTPUT_FILE}"
cat "$OUTPUT_FILE"

