#!/bin/bash
set -e

echo "Starting MCP Gateway with OAuth..."

# Start mcp-proxy in background on localhost:3100
echo "Starting mcp-proxy on localhost:3100..."
uv run mcp-proxy --port=3100 --host=0.0.0.0 --pass-environment --named-server-config /app/servers.json &
MCP_PROXY_PID=$!

# Wait for mcp-proxy to be ready
echo "Waiting for mcp-proxy to start..."
sleep 5

# Start Caddy in background
echo "Starting Caddy for HTTPS termination..."
caddy run --config /app/Caddyfile --adapter caddyfile &
CADDY_PID=$!

# Wait a bit for Caddy to start
sleep 3

# Start gateway.py in foreground on port 8000
echo "Starting FastMCP Gateway on port 8000..."
uv run python gateway.py

# Cleanup on exit
trap "kill $MCP_PROXY_PID $CADDY_PID 2>/dev/null || true" EXIT
