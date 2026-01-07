#!/bin/bash
# run-benchmark.sh - Main benchmark orchestration script
# Run this from the client host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/benchmark.yaml"
CERT_DIR="${PROJECT_DIR}/certs"
RESULTS_DIR="${PROJECT_DIR}/results"

# Read configuration
CLIENT_HOST=$(yq '.hosts.client' "$CONFIG_FILE")
PROXY_HOST=$(yq '.hosts.proxy' "$CONFIG_FILE")
ORIGIN_HOST=$(yq '.hosts.origin' "$CONFIG_FILE")
ORIGIN_PORT=$(yq '.ports.origin' "$CONFIG_FILE")

CLIENTS=$(yq '.benchmark.clients' "$CONFIG_FILE")
THREADS=$(yq '.benchmark.threads' "$CONFIG_FILE")
DURATION=$(yq '.benchmark.duration' "$CONFIG_FILE")

WARMUP_DURATION=$(yq '.cache.warmup_duration' "$CONFIG_FILE")
WARMUP_URLS=$(yq '.cache.warmup_urls' "$CONFIG_FILE")

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${RESULTS_DIR}/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Proxy Benchmark Suite ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Client: ${CLIENT_HOST}"
echo "Proxy: ${PROXY_HOST}"
echo "Origin: ${ORIGIN_HOST}:${ORIGIN_PORT}"
echo "Clients: ${CLIENTS}, Threads: ${THREADS}, Duration: ${DURATION}s"
echo "Results: ${RUN_DIR}"
echo ""

# Save config snapshot
cp "$CONFIG_FILE" "${RUN_DIR}/benchmark.yaml"

# Function to get port for a proxy and protocol
get_port() {
    local proxy=$1
    local protocol=$2
    
    if [[ "$protocol" == *"plain"* ]]; then
        yq ".ports.proxies.${proxy}.http" "$CONFIG_FILE"
    else
        yq ".ports.proxies.${proxy}.https" "$CONFIG_FILE"
    fi
}

# Function to run a single benchmark
run_single_benchmark() {
    local proxy=$1
    local scenario=$2
    local port=$(get_port "$proxy" "$scenario")
    
    echo ""
    echo ">>> Running: ${proxy} / ${scenario} (port ${port})"
    
    # Determine URL scheme and h2load options
    local scheme h2load_opts endpoint
    case "$scenario" in
        http1-plain-*)
            scheme="http"
            h2load_opts="--h1"
            ;;
        http1-tls-*)
            scheme="https"
            h2load_opts="--h1"
            ;;
        http2-tls-*)
            scheme="https"
            h2load_opts=""
            ;;
    esac
    
    # Determine endpoint (cached vs uncached)
    if [[ "$scenario" == *"cached"* ]]; then
        endpoint="cacheable"
    else
        endpoint="uncacheable"
    fi
    
    # TLS options
    local tls_opts=""
    if [[ "$scheme" == "https" ]]; then
        if [ -f "${CERT_DIR}/ca.crt" ]; then
            tls_opts="--ca-cert=${CERT_DIR}/ca.crt"
        else
            tls_opts="--insecure"
        fi
    fi
    
    # Generate URL list for cached scenarios (multiple URLs)
    local url_file=$(mktemp)
    trap "rm -f $url_file" RETURN
    
    for i in $(seq 1 "$WARMUP_URLS"); do
        echo "${scheme}://${PROXY_HOST}:${port}/${endpoint}/${i}" >> "$url_file"
    done
    
    # Warm cache for cached scenarios
    if [[ "$scenario" == *"cached"* ]]; then
        echo "  Warming cache for ${WARMUP_DURATION}s..."
        h2load -D "$WARMUP_DURATION" -c 100 -t 4 $h2load_opts $tls_opts -i "$url_file" > /dev/null 2>&1 || true
        sleep 1
    fi
    
    # Run benchmark
    local output_file="${RUN_DIR}/${proxy}_${scenario}.txt"
    echo "  Running benchmark for ${DURATION}s..."
    
    h2load \
        -D "$DURATION" \
        -c "$CLIENTS" \
        -t "$THREADS" \
        $h2load_opts \
        $tls_opts \
        -i "$url_file" \
        2>&1 | tee "$output_file"
    
    # Parse and save as JSON
    parse_h2load_output "$output_file" "$proxy" "$scenario" > "${RUN_DIR}/${proxy}_${scenario}.json"
    
    rm -f "$url_file"
    echo "  Results saved to ${output_file}"
}

# Function to parse h2load output into JSON
parse_h2load_output() {
    local file=$1
    local proxy=$2
    local scenario=$3
    
    # Extract metrics using grep/awk
    local req_sec=$(grep "requests/sec" "$file" | head -1 | awk '{print $1}' || echo "0")
    local total_reqs=$(grep "requests:" "$file" | head -1 | awk '{print $2}' || echo "0")
    
    # Extract timing stats (time for request)
    local timing_line=$(grep -A1 "time for request:" "$file" | tail -1 || echo "")
    local latency_min=$(echo "$timing_line" | awk '{print $1}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    local latency_max=$(echo "$timing_line" | awk '{print $2}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    local latency_mean=$(echo "$timing_line" | awk '{print $3}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    local latency_sd=$(echo "$timing_line" | awk '{print $4}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    
    cat << EOF
{
  "proxy": "${proxy}",
  "scenario": "${scenario}",
  "timestamp": "$(date -Iseconds)",
  "params": {
    "clients": ${CLIENTS},
    "threads": ${THREADS},
    "duration": ${DURATION}
  },
  "h2load": {
    "requests_per_sec": ${req_sec:-0},
    "total_requests": ${total_reqs:-0},
    "latency_min": "${latency_min}",
    "latency_max": "${latency_max}",
    "latency_mean": "${latency_mean}",
    "latency_sd": "${latency_sd}"
  }
}
EOF
}

# Get lists from config
mapfile -t PROXIES < <(yq -r '.proxies[]' "$CONFIG_FILE")
mapfile -t SCENARIOS < <(yq -r '.scenarios[]' "$CONFIG_FILE")

echo "Proxies: ${PROXIES[*]}"
echo "Scenarios: ${SCENARIOS[*]}"

# Run benchmarks for each proxy and scenario
for proxy in "${PROXIES[@]}"; do
    echo ""
    echo "=========================================="
    echo "  Benchmarking: ${proxy}"
    echo "=========================================="
    
    for scenario in "${SCENARIOS[@]}"; do
        run_single_benchmark "$proxy" "$scenario"
        sleep 2  # Brief pause between tests
    done
done

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: ${RUN_DIR}"
echo ""
echo "To generate report:"
echo "  ./scripts/generate-report.py ${RUN_DIR}"

