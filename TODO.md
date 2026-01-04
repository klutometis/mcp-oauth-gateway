# MCP Gateway - TODO

## ✅ Completed (2026-01-04)

### FastMCP Gateway with stdio Transport

Successfully deployed FastMCP OAuth gateway using stdio transport to eliminate HTTP proxy bottleneck.

**What worked:**
- ✅ FastMCP.as_proxy() with stdio servers (bypassing mcp-proxy)
- ✅ Google OAuth with DCR support
- ✅ Concurrent request handling (no blocking!)
- ✅ Production deployment at https://mcp.example.com
- ✅ Local testing with `./test-local.sh`
- ✅ Automated deployment with `./deploy-gateway.sh`

**Performance:**
- Before: 30-60s response times with HTTP proxy chain
- After: Fast (~3ms) with direct stdio connections

**Architecture:**
```
Production: Internet → Caddy (HTTPS) → FastMCP (port 8000) → stdio MCP servers
Local test: localhost:8000 → FastMCP → stdio MCP servers
```

**Key files:**
- `gateway.py` - FastMCP proxy with stdio configuration
- `test-local.sh` - Local Docker testing script
- `deploy-gateway.sh` - GCP deployment automation
- `entrypoint.sh` - Smart startup (Caddy for prod, direct for local)
- `Dockerfile` - Includes Node.js, uv, and Caddy

## Maintenance Tasks

### Ongoing
- [ ] Monitor performance in production
- [ ] Keep MCP server packages up to date (`npx -y` auto-updates)
- [ ] Review Caddy logs for SSL certificate renewal
- [ ] Update OAuth redirect URIs if domain changes

### Future Enhancements
- [ ] Add health check endpoint
- [ ] Add metrics/monitoring (request latency, error rates)
- [ ] Consider Redis for session storage if scaling to multiple instances
- [ ] Document client configuration for different MCP clients

## Reference

### Testing Locally
```bash
# 1. Ensure environment variables are set
source ~/etc/dotfiles/dot-env-secrets

# 2. Run test script
./test-local.sh

# 3. Test with MCP Inspector
npx @modelcontextprotocol/inspector http://localhost:8000
```

### Deploying to Production
```bash
# 1. Ensure all environment variables are set (from dot-env-secrets)
source ~/etc/dotfiles/dot-env-secrets

# 2. Ensure DNS points to static IP
# mcp.example.com → GCP static IP

# 3. Deploy
./deploy-gateway.sh

# 4. Watch logs
gcloud compute ssh mcp-gateway \
  --project="${GCP_PROJECT_ID}" \
  --zone="us-central1-a" \
  --command='docker logs -f mcp-gateway'
```

### Required Environment Variables
- `GCP_PROJECT_ID` - GCP project for deployment
- `GCP_REGION` - GCP region (default: us-central1)
- `MCP_DOMAIN` - Domain for gateway (e.g., mcp.example.com)
- `MCP_OIDC_CLIENT_ID` - Google OAuth client ID
- `MCP_OIDC_CLIENT_SECRET` - Google OAuth client secret
- `MCP_ALLOWED_USERS` - Comma-separated email addresses
- API keys for each MCP server:
  - `CONTEXT7_API_KEY`
  - `FIRECRAWL_API_KEY`
  - `LINKUP_API_KEY`
  - `OPENMEMORY_API_KEY`
  - `PERPLEXITY_API_KEY`

### Client Configuration

Add to MCP client config (Gemini CLI, etc.):

```json
{
  "mcpServers": {
    "gateway": {
      "url": "https://mcp.example.com/mcp",
      "transport": "http"
    }
  }
}
```

The gateway aggregates all servers, so you only need one entry. Tools will be prefixed by server name (e.g., `context7_resolve-library-id`, `firecrawl_firecrawl_scrape`).

## Archived: mcp-auth-proxy Exploration

We explored using per-server mcp-auth-proxy instances but discovered FastMCP with stdio was simpler and equally performant. See NOTES.md for full details.

The docker-compose.yml, Caddyfile.local, and per-service .env files were created during this exploration but are not used in the final solution.
