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
  -e MCP_ALLOWED_USERS="${MCP_ALLOWED_USERS}" \
  -e CONTEXT7_API_KEY="${CONTEXT7_API_KEY}" \
  -e FIRECRAWL_API_KEY="${FIRECRAWL_API_KEY}" \
  -e LINKUP_API_KEY="${LINKUP_API_KEY}" \
  -e OPENMEMORY_API_KEY="${OPENMEMORY_API_KEY}" \
  -e PERPLEXITY_API_KEY="${PERPLEXITY_API_KEY}" \
  mcp-gateway-test

echo "⏳ Waiting for gateway to start..."
sleep 5

echo ""
echo "🔍 Testing static pages..."
echo "  Home page:"
curl -s -o /dev/null -w "    Status: %{http_code}\n" http://localhost:8000/ || true
echo "  Privacy policy:"
curl -s -o /dev/null -w "    Status: %{http_code}\n" http://localhost:8000/privacy || true
echo "  Terms of service:"
curl -s -o /dev/null -w "    Status: %{http_code}\n" http://localhost:8000/terms || true

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
echo "🧪 Gateway is running - test endpoints:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Static pages (for OAuth verification):"
echo "    http://localhost:8000/           (home page)"
echo "    http://localhost:8000/privacy    (privacy policy)"
echo "    http://localhost:8000/terms      (terms of service)"
echo ""
echo "  MCP clients:"
echo "    npx github:tilesprivacy/mcp-cli http://localhost:8000"
echo "    npx @modelcontextprotocol/inspector http://localhost:8000"
echo ""
echo "  OAuth discovery:"
echo "    curl http://localhost:8000/.well-known/oauth-authorization-server"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Following gateway logs (Ctrl+C to stop)..."
echo ""

# Tail logs; container keeps running even if Ctrl+C
docker logs -f mcp-gateway-test

echo ""
echo "🧹 Stopping gateway..."
docker stop mcp-gateway-test

echo "✅ Done!"
