#!/bin/bash
set -e

echo "Starting MCP Gateway with OAuth (stdio transport)..."

# Check if we need HTTPS (production) or HTTP (local testing)
if [[ "$MCP_DOMAIN" == localhost* ]]; then
    echo "Local testing mode - running gateway directly on HTTP"
    exec uv run python gateway.py
else
    echo "Production mode - starting Caddy for HTTPS termination"
    
    # Start Caddy in background
    caddy run --config /app/Caddyfile --adapter caddyfile &
    CADDY_PID=$!
    
    # Wait for Caddy to start
    sleep 3
    
    # Start gateway.py in foreground
    uv run python gateway.py
    
    # Cleanup on exit
    trap "kill $CADDY_PID 2>/dev/null || true" EXIT
fi
