# MCP Gateway with OAuth

FastMCP-based gateway that aggregates multiple MCP servers with Google OAuth authentication.

## Features

- **Multi-server aggregation**: Exposes all MCP servers through a single authenticated endpoint
- **Google OAuth**: Proper OAuth 2.0 with Dynamic Client Registration (DCR) support
- **MCP protocol native**: Understands HTTP+SSE transport unlike generic HTTP proxies
- **Production ready**: Built-in security, token management, and error handling

## Architecture

```
Client (TypingMind/Gemini CLI) 
    ↓ OAuth/DCR
FastMCP Gateway (port 443)
    ↓ HTTP+SSE
mcp-proxy (localhost:3100)
    ↓ stdio
Individual MCP servers (context7, firecrawl, etc.)
```

## Project Structure

```
.
├── gateway.py          # FastMCP gateway with OAuth
├── servers.json        # mcp-proxy server configuration
├── pyproject.toml      # Python dependencies (uv managed)
├── Dockerfile          # Container deployment
├── entrypoint.sh       # Startup script (mcp-proxy → gateway)
└── .env.example        # Configuration template
```

## Environment Variables

Required:
- `MCP_OIDC_CLIENT_ID`: Google OAuth Client ID
- `MCP_OIDC_CLIENT_SECRET`: Google OAuth Client Secret
- `MCP_DOMAIN`: Public domain (e.g., `mcp.example.com`)
- `MCP_ALLOWED_USERS`: Comma-separated list of allowed email addresses

Optional API keys (passed to mcp-proxy):
- `CONTEXT7_API_KEY`
- `FIRECRAWL_API_KEY`
- `LINKUP_API_KEY`
- `OPENMEMORY_API_KEY`
- `PERPLEXITY_API_KEY`

## Local Development

### Setup

```bash
# Install dependencies with uv
uv sync

# Ensure your central secrets are loaded in your shell
# (dot-env-secrets should already be in your environment)
# Required variables:
# - MCP_OIDC_CLIENT_ID
# - MCP_OIDC_CLIENT_SECRET  
# - MCP_ALLOWED_USERS
# - CONTEXT7_API_KEY, FIRECRAWL_API_KEY, etc.
```

### Running Locally

**Terminal 1 - Start mcp-proxy:**
```bash
# mcp-proxy aggregates the individual MCP servers
./run.sh uv run mcp-proxy --port=3100 --host=127.0.0.1 --pass-environment \
  --named-server-config servers.json
```

**Terminal 2 - Start FastMCP Gateway:**
```bash
# Loads secrets from dot-env-secrets automatically
./run.sh

# Gateway will start on http://localhost:8000
```

**Note:** The `run.sh` script sets `MCP_DOMAIN=localhost:8000` for local development. Your centralized secrets from `dot-env-secrets` should already be loaded in your shell environment.

### Testing the OAuth Flow

1. **Verify OAuth metadata is exposed:**
   ```bash
   curl http://localhost:8000/.well-known/oauth-authorization-server | jq
   ```

2. **Configure TypingMind:**
   - Add new MCP server with URL: `http://localhost:8000`
   - Enable OAuth authentication
   - Connect and follow the browser OAuth flow

3. **Expected flow:**
   - TypingMind detects OAuth requirement
   - Opens browser for Google login
   - Shows consent screen
   - After approval, returns tokens
   - Tools become available with prefixes: `context7_*`, `firecrawl_*`, etc.

## Google OAuth Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create OAuth credentials
3. Add redirect URIs:
   - Local: `http://localhost:8000/auth/callback`
   - Production: `https://mcp.example.com/auth/callback`
4. Note Client ID and Secret

## Deployment

Build and deploy Docker container:

```bash
docker build -t mcp-gateway .
docker run -d \
  --name mcp-gateway \
  -p 443:443 \
  --env-file .env \
  mcp-gateway
```

For GCP Cloud Run, see deployment script (TODO).

## Client Configuration

### TypingMind

1. Add new MCP server
2. Server URL: `https://mcp.example.com`
3. Enable OAuth Client toggle
4. Follow OAuth flow in browser

### Gemini CLI

Configure in `settings.json`:
```json
{
  "mcpServers": {
    "remote-gateway": {
      "url": "https://mcp.example.com",
    }
  }
}
```

## Troubleshooting

Check logs:
```bash
docker logs mcp-gateway
```

Test OAuth metadata:
```bash
curl https://mcp.example.com/.well-known/oauth-authorization-server
```

Verify mcp-proxy is running:
```bash
curl http://localhost:3100/health
```

## Migration from mcp-auth-proxy

See `TODO.md` for full migration notes. Key difference: FastMCP natively understands MCP protocol (HTTP+SSE), unlike mcp-auth-proxy which only does HTTP-level proxying.
