# Proxy Benchmark Project - Design Document

Benchmark Apache Traffic Server, Nginx, Envoy, and HAProxy with h2load, measuring throughput, latency percentiles, and resource consumption.

## Configuration

Central config file `benchmark.yaml`:

```yaml
# benchmark.yaml - Main configuration file

hosts:
  client: eris    # Runs h2load
  proxy: zeus     # Runs proxy servers
  origin: eris    # Runs origin nginx backend

ports:
  origin: 9000
  proxies:
    ats:
      http: 8080
      https: 8443
    nginx:
      http: 8081
      https: 8444
    envoy:
      http: 8082
      https: 8445
    haproxy:
      http: 8083
      https: 8446

benchmark:
  clients: 1000
  threads: 12
  duration: 10        # seconds

response:
  size_kb: 1          # default: 1KB

cache:
  warmup_duration: 5  # seconds
  warmup_urls: 100    # unique URLs to cache

scenarios:
  - http1-plain-cached
  - http1-plain-uncached
  - http1-tls-cached
  - http1-tls-uncached
  - http2-tls-cached
  - http2-tls-uncached

proxies:
  - ats
  - nginx
  - envoy
  - haproxy
```

## Test Environment

```
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│ hosts.client  │         │  hosts.proxy  │         │ hosts.origin  │
│               │         │               │         │               │
│ ┌───────────┐ │ request │ ┌───────────┐ │ request │ ┌───────────┐ │
│ │  h2load   │─┼────────▶│ │   Proxy   │─┼────────▶│ │  nginx    │ │
│ │(12 threads)│ │         │ │ HTTP:808x │ │         │ │  :9000    │ │
│ └───────────┘ │         │ │ HTTPS:844x│ │         │ └───────────┘ │
│               │         │ └───────────┘ │         │               │
└───────────────┘         └───────────────┘         └───────────────┘
     (eris)                    (zeus)                   (eris)
```

## Project Structure

```
~/proxy_benchmark/
├── README.md
├── .gitignore
├── benchmark.yaml
├── docs/
│   └── design.md               # This plan document
├── hardware/
│   ├── collect-specs.sh
│   └── *.json
├── configs/
│   ├── ats/
│   ├── nginx/
│   ├── envoy/
│   └── haproxy/
├── certs/
├── scripts/
│   ├── setup-client.sh
│   ├── setup-proxy.sh
│   ├── setup-origin.sh
│   ├── generate-certs.sh
│   ├── generate-content.sh
│   ├── warm-cache.sh
│   ├── run-benchmark.sh
│   ├── collect-metrics.sh
│   └── generate-report.py
├── backend/
│   ├── nginx.conf.template
│   └── content/
├── results/
└── reports/
```

## Benchmark Scenarios

| Scenario | Protocol | TLS | Caching |
|----------|----------|-----|---------|
| http1-plain-cached | HTTP/1.1 | No | 100% hit |
| http1-plain-uncached | HTTP/1.1 | No | 0% hit |
| http1-tls-cached | HTTP/1.1 | Yes | 100% hit |
| http1-tls-uncached | HTTP/1.1 | Yes | 0% hit |
| http2-tls-cached | HTTP/2 | Yes | 100% hit |
| http2-tls-uncached | HTTP/2 | Yes | 0% hit |

## Fedora Dependencies

```bash
# On client host
sudo dnf install -y yq nghttp2 sysstat ethtool

# On proxy host
sudo dnf install -y yq trafficserver nginx envoy haproxy sysstat ethtool

# On origin host
sudo dnf install -y nginx
```

## Metrics Collected

- **h2load**: Requests/sec, latency p50/p95/p99
- **pidstat**: CPU %, Memory RSS
- **sar -n DEV**: Network RX/TX bandwidth

## Cache Warming Strategy

For cached scenarios, warm the cache before benchmarking:

```bash
# Generate URL list file with 100 unique cacheable URLs
for i in $(seq 1 $WARMUP_URLS); do
    echo "https://${PROXY_HOST}:${port}/cacheable/${i}"
done > /tmp/urls.txt

# Warm cache for 5 seconds using all URLs
h2load -D $WARMUP_DURATION -c 100 -t 4 -i /tmp/urls.txt
```

The benchmark then requests the same 100 URLs randomly to achieve ~100% cache hit rate.

## Output Format

Results stored as JSON for easy parsing:

```json
{
  "proxy": "ats",
  "scenario": "http2-tls-cached",
  "params": {
    "clients": 1000,
    "body_size_kb": 1
  },
  "h2load": {
    "requests_per_sec": 85000,
    "latency_p50_ms": 1.2,
    "latency_p95_ms": 3.8,
    "latency_p99_ms": 7.1
  },
  "resources": {
    "cpu_percent_avg": 92.5,
    "memory_mb_max": 256,
    "network_rx_mbps": 850.2,
    "network_tx_mbps": 892.5
  }
}
```

## Hardware Spec Collection

Script `collect-specs.sh` gathers and saves as JSON:

```bash
# CPU info
lscpu | grep -E "Model name|Socket|Core|Thread|MHz|Cache"

# Memory
free -h
dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type"

# Network interface
ip link show
ethtool <interface> 2>/dev/null | grep -E "Speed|Duplex"

# Kernel
uname -r
```

**Output format** (`hardware/zeus.json`):

```json
{
  "hostname": "zeus",
  "timestamp": "2026-01-07T10:00:00Z",
  "cpu": {
    "model": "AMD Ryzen 9 5950X",
    "cores": 16,
    "threads": 32,
    "base_mhz": 3400
  },
  "memory": {
    "total_gb": 64,
    "type": "DDR4",
    "speed_mhz": 3200
  },
  "network": {
    "interface": "enp5s0",
    "speed_gbps": 10,
    "driver": "igc"
  },
  "kernel": "6.17.12-300.fc43.x86_64"
}
```

