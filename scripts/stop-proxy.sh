#!/bin/bash
# stop-proxy.sh - Stop a proxy server
# Usage: ./stop-proxy.sh <proxy_name>

set -e

PROXY="${1:?Usage: $0 <proxy_name> (ats, nginx, envoy, haproxy)}"

echo "=== Stopping ${PROXY} ==="

case "$PROXY" in
    nginx)
        if [ -f /tmp/nginx-proxy.pid ]; then
            kill $(cat /tmp/nginx-proxy.pid) 2>/dev/null || true
            rm -f /tmp/nginx-proxy.pid
            echo "nginx stopped"
        else
            pkill -f "nginx.*nginx-proxy.conf" 2>/dev/null || true
            echo "nginx stopped (by process name)"
        fi
        ;;
        
    ats)
        pkill -f traffic_server 2>/dev/null || true
        echo "ATS stopped"
        ;;
        
    envoy)
        if [ -f /tmp/envoy.pid ]; then
            kill $(cat /tmp/envoy.pid) 2>/dev/null || true
            rm -f /tmp/envoy.pid
            echo "envoy stopped"
        else
            pkill -f envoy 2>/dev/null || true
            echo "envoy stopped (by process name)"
        fi
        ;;
        
    haproxy)
        if [ -f /tmp/haproxy.pid ]; then
            kill $(cat /tmp/haproxy.pid) 2>/dev/null || true
            rm -f /tmp/haproxy.pid
            echo "haproxy stopped"
        else
            pkill -f haproxy 2>/dev/null || true
            echo "haproxy stopped (by process name)"
        fi
        ;;
        
    all)
        $0 nginx
        $0 envoy
        $0 haproxy
        $0 ats
        ;;
        
    *)
        echo "Unknown proxy: $PROXY"
        exit 1
        ;;
esac

echo "=== ${PROXY} stopped ==="

