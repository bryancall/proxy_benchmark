#!/usr/bin/env python3
"""
generate-report.py - Generate benchmark comparison report with charts

Usage: ./generate-report.py <results_dir>
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime

try:
    import matplotlib.pyplot as plt
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("Warning: matplotlib not installed. Charts will not be generated.")
    print("Install with: pip install matplotlib")


def load_results(results_dir: Path) -> list[dict]:
    """Load all JSON result files from the results directory."""
    results = []
    for json_file in results_dir.glob("*.json"):
        if json_file.name == "benchmark.yaml":
            continue
        try:
            with open(json_file) as f:
                data = json.load(f)
                data["_file"] = json_file.name
                results.append(data)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load {json_file}: {e}")
    return results


def generate_text_report(results: list[dict], output_dir: Path) -> str:
    """Generate a text summary report."""
    lines = []
    lines.append("=" * 70)
    lines.append("PROXY BENCHMARK REPORT")
    lines.append("=" * 70)
    lines.append(f"Generated: {datetime.now().isoformat()}")
    lines.append(f"Results directory: {output_dir}")
    lines.append("")
    
    # Group by scenario
    scenarios = {}
    for r in results:
        scenario = r.get("scenario", "unknown")
        if scenario not in scenarios:
            scenarios[scenario] = []
        scenarios[scenario].append(r)
    
    # Print results by scenario
    for scenario in sorted(scenarios.keys()):
        lines.append("-" * 70)
        lines.append(f"Scenario: {scenario}")
        lines.append("-" * 70)
        lines.append(f"{'Proxy':<12} {'Req/sec':>12} {'Latency Mean':>15} {'Total Reqs':>12}")
        lines.append("-" * 70)
        
        # Sort by requests/sec (descending)
        scenario_results = sorted(
            scenarios[scenario],
            key=lambda x: float(x.get("h2load", {}).get("requests_per_sec", 0)),
            reverse=True
        )
        
        for r in scenario_results:
            proxy = r.get("proxy", "unknown")
            h2load = r.get("h2load", {})
            req_sec = h2load.get("requests_per_sec", 0)
            latency_mean = h2load.get("latency_mean", "N/A")
            total_reqs = h2load.get("total_requests", 0)
            
            lines.append(f"{proxy:<12} {req_sec:>12.2f} {latency_mean:>15} {total_reqs:>12}")
        
        lines.append("")
    
    # Summary
    lines.append("=" * 70)
    lines.append("SUMMARY BY PROXY")
    lines.append("=" * 70)
    
    proxy_totals = {}
    for r in results:
        proxy = r.get("proxy", "unknown")
        req_sec = float(r.get("h2load", {}).get("requests_per_sec", 0))
        if proxy not in proxy_totals:
            proxy_totals[proxy] = {"total_rps": 0, "count": 0}
        proxy_totals[proxy]["total_rps"] += req_sec
        proxy_totals[proxy]["count"] += 1
    
    lines.append(f"{'Proxy':<12} {'Avg Req/sec':>15} {'Tests Run':>12}")
    lines.append("-" * 40)
    
    for proxy in sorted(proxy_totals.keys()):
        data = proxy_totals[proxy]
        avg_rps = data["total_rps"] / data["count"] if data["count"] > 0 else 0
        lines.append(f"{proxy:<12} {avg_rps:>15.2f} {data['count']:>12}")
    
    report = "\n".join(lines)
    
    # Save report
    report_file = output_dir / "report.txt"
    with open(report_file, "w") as f:
        f.write(report)
    
    return report


def generate_charts(results: list[dict], output_dir: Path):
    """Generate comparison charts using matplotlib."""
    if not HAS_MATPLOTLIB:
        return
    
    # Organize data
    proxies = sorted(set(r.get("proxy", "unknown") for r in results))
    scenarios = sorted(set(r.get("scenario", "unknown") for r in results))
    
    # Create data matrix for requests/sec
    rps_data = {proxy: {} for proxy in proxies}
    for r in results:
        proxy = r.get("proxy", "unknown")
        scenario = r.get("scenario", "unknown")
        rps = float(r.get("h2load", {}).get("requests_per_sec", 0))
        rps_data[proxy][scenario] = rps
    
    # Chart 1: Grouped bar chart - Requests/sec by scenario
    fig, ax = plt.subplots(figsize=(14, 8))
    
    x = range(len(scenarios))
    width = 0.2
    multiplier = 0
    
    colors = ['#2ecc71', '#3498db', '#e74c3c', '#9b59b6']
    
    for i, proxy in enumerate(proxies):
        offset = width * multiplier
        rps_values = [rps_data[proxy].get(s, 0) for s in scenarios]
        bars = ax.bar([xi + offset for xi in x], rps_values, width, 
                      label=proxy.upper(), color=colors[i % len(colors)])
        multiplier += 1
    
    ax.set_ylabel('Requests/sec', fontsize=12)
    ax.set_xlabel('Scenario', fontsize=12)
    ax.set_title('Proxy Performance Comparison - Requests per Second', fontsize=14, fontweight='bold')
    ax.set_xticks([xi + width * (len(proxies) - 1) / 2 for xi in x])
    ax.set_xticklabels(scenarios, rotation=45, ha='right')
    ax.legend(loc='upper right')
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'chart_rps.png', dpi=150)
    plt.close()
    
    # Chart 2: Summary bar chart - Average RPS per proxy
    fig, ax = plt.subplots(figsize=(10, 6))
    
    avg_rps = []
    for proxy in proxies:
        values = [v for v in rps_data[proxy].values() if v > 0]
        avg_rps.append(sum(values) / len(values) if values else 0)
    
    bars = ax.bar(proxies, avg_rps, color=colors[:len(proxies)])
    ax.set_ylabel('Average Requests/sec', fontsize=12)
    ax.set_xlabel('Proxy', fontsize=12)
    ax.set_title('Average Performance by Proxy', fontsize=14, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Add value labels on bars
    for bar, val in zip(bars, avg_rps):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 500,
                f'{val:,.0f}', ha='center', va='bottom', fontsize=10)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'chart_avg_rps.png', dpi=150)
    plt.close()
    
    # Chart 3: Cached vs Uncached comparison
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    
    for idx, cache_type in enumerate(['cached', 'uncached']):
        ax = axes[idx]
        filtered_scenarios = [s for s in scenarios if cache_type in s]
        
        x = range(len(filtered_scenarios))
        width = 0.2
        multiplier = 0
        
        for i, proxy in enumerate(proxies):
            offset = width * multiplier
            rps_values = [rps_data[proxy].get(s, 0) for s in filtered_scenarios]
            ax.bar([xi + offset for xi in x], rps_values, width,
                   label=proxy.upper(), color=colors[i % len(colors)])
            multiplier += 1
        
        ax.set_ylabel('Requests/sec', fontsize=11)
        ax.set_title(f'{cache_type.capitalize()} Scenarios', fontsize=12, fontweight='bold')
        ax.set_xticks([xi + width * (len(proxies) - 1) / 2 for xi in x])
        ax.set_xticklabels([s.replace(f'-{cache_type}', '') for s in filtered_scenarios],
                          rotation=45, ha='right')
        ax.legend(loc='upper right', fontsize=9)
        ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'chart_cache_comparison.png', dpi=150)
    plt.close()
    
    print(f"Charts saved to {output_dir}")


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <results_directory>")
        print("Example: ./generate-report.py results/20260107_143000")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    print(f"Loading results from {results_dir}...")
    results = load_results(results_dir)
    
    if not results:
        print("No result files found!")
        sys.exit(1)
    
    print(f"Found {len(results)} result files")
    
    # Generate reports
    report_dir = results_dir / "reports"
    report_dir.mkdir(exist_ok=True)
    
    print("\nGenerating text report...")
    report = generate_text_report(results, report_dir)
    print(report)
    
    if HAS_MATPLOTLIB:
        print("\nGenerating charts...")
        generate_charts(results, report_dir)
    
    print(f"\nReports saved to: {report_dir}")


if __name__ == "__main__":
    main()

