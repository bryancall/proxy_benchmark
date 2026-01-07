# Proxy Benchmark Suite

A reproducible benchmarking framework for comparing Apache Traffic Server (ATS), Nginx, Envoy, and HAProxy.

## Overview

This suite measures proxy performance across multiple scenarios:
- HTTP/1.1 (plain and TLS)
- HTTP/2 (TLS)
- 100% cache hit vs 0% cache hit (uncacheable)

## Metrics Collected

- **Throughput**: Requests per second
- **Latency**: p50, p95, p99 percentiles
- **Resource Usage**: CPU %, Memory RSS
- **Network**: RX/TX bandwidth (MB/s)

## Test Environment

```
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│    Client     │         │     Proxy     │         │    Origin     │
│               │         │               │         │               │
│   h2load      │────────▶│  ATS/Nginx/   │────────▶│    nginx      │
│  (12 threads) │         │  Envoy/HAProxy│         │    :9000      │
└───────────────┘         └───────────────┘         └───────────────┘
```

## Quick Start

1. **Edit configuration:**
   ```bash
   vi benchmark.yaml
   ```

2. **Setup hosts:**
   ```bash
   # On client host
   ./scripts/setup-client.sh

   # On proxy host
   ./scripts/setup-proxy.sh

   # On origin host
   ./scripts/setup-origin.sh
   ```

3. **Generate certificates and content:**
   ```bash
   ./scripts/generate-certs.sh
   ./scripts/generate-content.sh
   ```

4. **Run benchmarks:**
   ```bash
   ./scripts/run-benchmark.sh
   ```

5. **Generate report:**
   ```bash
   ./scripts/generate-report.py
   ```

## Configuration

Edit `benchmark.yaml` to customize:

- **hosts**: Client, proxy, and origin hostnames
- **ports**: HTTP/HTTPS ports for each proxy
- **benchmark**: Number of clients, threads, duration
- **response**: Response body size
- **cache**: Warmup duration and URL count
- **scenarios**: Which test scenarios to run
- **proxies**: Which proxies to benchmark

## Dependencies (Fedora)

```bash
# Client host
sudo dnf install -y yq nghttp2 sysstat ethtool

# Proxy host
sudo dnf install -y yq trafficserver nginx envoy haproxy sysstat ethtool

# Origin host
sudo dnf install -y nginx
```

## Project Structure

```
proxy_benchmark/
├── benchmark.yaml          # Main configuration
├── docs/                   # Documentation
├── hardware/               # Hardware specs collection
├── configs/                # Proxy configurations
│   ├── ats/
│   ├── nginx/
│   ├── envoy/
│   └── haproxy/
├── certs/                  # TLS certificates
├── scripts/                # Setup and benchmark scripts
├── backend/                # Origin server config
├── results/                # Raw benchmark output
└── reports/                # Generated reports
```

## License

Apache 2.0

