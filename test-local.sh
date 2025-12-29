#!/bin/bash
# test-local.sh - Test OAuth gateway locally with Docker before GCP deployment

set -e

echo "🔨 Building gateway Docker image..."
docker build -t mcp-gateway-test .

echo ""
echo "🔑 Checking environment variables..."
if [ -z "$MCP_OIDC_CLIENT_ID" ]; then
    echo "❌ MCP_OIDC_CLIENT_ID not set"
    echo "   Set it with: export MCP_OIDC_CLIENT_ID='your-client-id'"
    exit 1
fi

if [ -z "$MCP_OIDC_CLIENT_SECRET" ]; then
    echo "❌ MCP_OIDC_CLIENT_SECRET not set"
    echo "   Set it with: export MCP_OIDC_CLIENT_SECRET='your-client-secret'"
    exit 1
fi

echo "✅ OAuth credentials found"

echo ""
echo "🧹 Cleaning up any existing container..."
docker rm -f mcp-gateway-test 2>/dev/null || true
sleep 2

echo ""
echo "🚀 Starting gateway on localhost:8000..."
docker run -d --rm \
  --name mcp-gateway-test \
  -p 8000:8000 \
  -e MCP_OIDC_CLIENT_ID="${MCP_OIDC_CLIENT_ID}" \
  -e MCP_OIDC_CLIENT_SECRET="${MCP_OIDC_CLIENT_SECRET}" \
  -e MCP_DOMAIN="localhost:8000" \
  mcp-gateway-test

echo "⏳ Waiting for gateway to start..."
sleep 5

echo ""
echo "🔍 Testing OAuth discovery endpoint..."
curl -s http://localhost:8000/.well-known/oauth-authorization-server | jq . || {
    echo "❌ Gateway not responding"
    docker logs mcp-gateway-test
    docker stop mcp-gateway-test
    exit 1
}

echo ""
echo "✅ Gateway is running!"
echo ""
echo "📋 Gateway logs (last 20 lines):"
docker logs --tail 20 mcp-gateway-test

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Now test with MCP client:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Option 1: Test with tilesprivacy/mcp-cli (has OAuth support):"
echo "  npx github:tilesprivacy/mcp-cli http://localhost:8000"
echo ""
echo "Option 2: Test with MCP Inspector (web UI):"
echo "  npx @modelcontextprotocol/inspector http://localhost:8000"
echo ""
echo "Option 3: Test OAuth endpoints manually:"
echo "  curl http://localhost:8000/.well-known/oauth-authorization-server"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Enter when done testing to stop the gateway..."
read

echo ""
echo "🧹 Stopping gateway..."
docker stop mcp-gateway-test

echo "✅ Done!"
