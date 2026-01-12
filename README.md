# MCP Gateway with OAuth

FastMCP-based OAuth gateway that aggregates multiple MCP servers behind a single authenticated endpoint.

## Features

- **Multi-server aggregation**: Single endpoint for all MCP servers
- **Google OAuth**: OAuth 2.0 with Dynamic Client Registration (DCR) and verified branding
- **Email-based access control**: Restrict access to specific Google accounts via `MCP_ALLOWED_USERS`
- **High performance**: Direct stdio connections to MCP servers (~3ms latency)
- **Concurrent requests**: Handles multiple simultaneous requests efficiently
- **Production ready**: Deployed with HTTPS, verified OAuth, and user access restrictions

## Architecture

### Current (Fast!)

```
Client → FastMCP Gateway (port 8000) → stdio MCP servers
```

FastMCP connects directly to MCP servers via stdio, avoiding HTTP proxy overhead.

### Production Deployment

```
Internet (HTTPS:443) → Caddy (TLS termination) → FastMCP (8000) → stdio MCP servers
```

Caddy handles automatic HTTPS with Let's Encrypt certificates.

## Quick Start

### Prerequisites

Ensure these environment variables are set (from `~/etc/dotfiles/dot-env-secrets`):
- `MCP_DOMAIN` - Your domain (e.g., `mcp.example.com`)
- `MCP_OIDC_CLIENT_ID` - Google OAuth Client ID
- `MCP_OIDC_CLIENT_SECRET` - Google OAuth Client Secret
- `MCP_ALLOWED_USERS` - Comma-separated email addresses (e.g., `bob@example.com,alice@example.com`)
- `GCP_PROJECT_ID` - GCP project for deployment
- API keys: `CONTEXT7_API_KEY`, `FIRECRAWL_API_KEY`, `LINKUP_API_KEY`, `OPENMEMORY_API_KEY`, `PERPLEXITY_API_KEY`

**Note on Access Control:**
- If `MCP_ALLOWED_USERS` is set, only listed emails can use MCP tools (others get 403 Forbidden)
- If `MCP_ALLOWED_USERS` is not set, **any Google account** can authenticate and use the gateway
- OAuth verification is public, so access control is enforced at the application layer

### Local Testing

```bash
# 1. Source environment variables
source ~/etc/dotfiles/dot-env-secrets

# 2. Run test script (builds Docker, starts gateway)
./test-local.sh

# 3. Test with MCP Inspector
npx @modelcontextprotocol/inspector http://localhost:8000
```

The test script:
- Builds Docker image
- Starts gateway on port 8000
- Displays OAuth endpoints and logs
- Waits for your testing, then cleans up

### Production Deployment

```bash
# 1. Ensure environment is loaded
source ~/etc/dotfiles/dot-env-secrets

# 2. Deploy to GCP
./deploy-gateway.sh
```

The deploy script:
- Builds and pushes Docker image to Artifact Registry
- Creates/updates GCP VM with static IP
- Configures firewall rules (ports 80, 443)
- Starts container with Caddy for HTTPS
- Tails logs for verification

**Important:** Ensure DNS A record points to the static IP:
```
mcp.example.com → <static-ip-from-deploy-script>
```

## Project Structure

```
.
├── gateway.py          # FastMCP gateway with stdio configuration
├── pyproject.toml      # Python dependencies (uv managed)
├── Dockerfile          # Multi-stage build (Python + Node.js + Caddy)
├── entrypoint.sh       # Smart startup (Caddy for prod, direct for local)
├── Caddyfile           # HTTPS termination config
├── test-local.sh       # Local Docker testing script
├── deploy-gateway.sh   # GCP deployment automation
├── NOTES.md            # Architecture decisions and debugging notes
└── TODO.md             # Task tracking and maintenance checklist
```

## Configuration

### gateway.py

Configures MCP servers with stdio transport:

```python
config = {
    "mcpServers": {
        "context7": {
            "command": "npx",
            "args": ["-y", "@upstash/context7-mcp"],
            "transport": "stdio"
        },
        "firecrawl": {
            "command": "npx",
            "args": ["-y", "firecrawl-mcp"],
            "transport": "stdio"
        },
        # ... more servers
    }
}

gateway = FastMCP.as_proxy(config, name="MCP Gateway", auth=auth)
gateway.run(transport="http", host="0.0.0.0", port=8000)
```

### Caddyfile

HTTPS termination with automatic Let's Encrypt:

```caddyfile
{$MCP_DOMAIN} {
    reverse_proxy localhost:8000
    log {
        output stdout
        format console
    }
}
```

## Client Configuration

### Gemini CLI / MCP Inspector

Add to MCP client config:

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

The gateway aggregates all servers. Tools are prefixed by server name:
- `context7_resolve-library-id`
- `context7_query-docs`
- `firecrawl_firecrawl_scrape`
- `firecrawl_firecrawl_search`
- `linkup_search-web`
- `openmemory_add-memory`
- `openmemory_search-memories`
- `perplexity_search`
- `perplexity_reason`

## Google OAuth Setup

1. Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
2. Create OAuth 2.0 Client ID (Web application)
3. Add authorized redirect URIs:
   - Local testing: `http://localhost:8000/auth/callback`
   - Production: `https://mcp.example.com/auth/callback`
4. Copy Client ID and Client Secret to `~/etc/dotfiles/dot-env-secrets`

## Troubleshooting

### Check gateway logs (local)

```bash
docker logs mcp-gateway-test
```

### Check gateway logs (production)

```bash
gcloud compute ssh mcp-gateway \
  --project="${GCP_PROJECT_ID}" \
  --zone="us-central1-a" \
  --command='docker logs -f mcp-gateway'
```

### Test OAuth metadata

```bash
# Local
curl http://localhost:8000/.well-known/oauth-authorization-server | jq

# Production
curl https://mcp.example.com/.well-known/oauth-authorization-server | jq
```

### Common issues

**SSL certificate errors in production:**
- Verify DNS points to correct static IP
- Check `MCP_DOMAIN` is set correctly (not `mcp.example.com`)
- Wait 2-3 minutes for Caddy to obtain Let's Encrypt certificate
- Check Caddy logs: `docker logs mcp-gateway 2>&1 | grep -i cert`

**Gateway not starting:**
- Verify all environment variables are set
- Check API keys are valid
- Ensure MCP server packages can be installed (npm/npx/uvx accessible)

**OAuth flow fails:**
- Verify redirect URI in Google Console matches exactly
- Check `MCP_ALLOWED_USERS` includes your email
- Ensure OAuth Client ID and Secret are correct

## Performance Notes

**Why this is fast:**

According to [FastMCP Issue #1583](https://github.com/jlowin/fastmcp/issues/1583):
- Direct tool call: ~2ms
- stdio proxy: ~3ms ✅ (what we use)
- HTTP proxy: 300-400ms ❌ (100-200x slower!)

We use stdio transport exclusively to avoid HTTP proxy overhead. The gateway handles concurrent requests efficiently because each stdio connection is independent.

## Development History

See `NOTES.md` for full architectural journey:
- Started with FastMCP + mcp-proxy (HTTP) - too slow
- Explored per-server mcp-auth-proxy instances - OAuth compatibility issues
- **Final solution**: FastMCP + stdio directly - fast and simple!

## License

MIT
