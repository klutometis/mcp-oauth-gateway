# Migration to FastMCP OAuth Proxy

## Current Issues with mcp-auth-proxy

1. **Protocol mismatch**: mcp-auth-proxy does HTTP-level proxying, doesn't understand MCP's HTTP+SSE protocol
2. **Session handling**: MCP requires establishing SSE session first (GET /sse) before sending messages (POST /messages/)
3. **Multi-server complexity**: Would need one mcp-auth-proxy instance per MCP server (different domains/ports)
4. **Incomplete integration**: OAuth/DCR works but requests fail at MCP protocol layer

## FastMCP Solution

FastMCP's OAuth Proxy provides:
- Multi-server aggregation from config (replaces mcp-proxy aggregation)
- Native MCP protocol understanding (HTTP+SSE transport)
- Built-in OAuth with DCR support for MCP clients
- Google OAuth provider out of the box
- Proper token management and security

## Implementation Plan

### 1. Create FastMCP Gateway Script

Create `prg/mcp-gateway/gateway.py`:

```python
from fastmcp import FastMCP
from fastmcp.server.auth.providers.google import GoogleProvider
import os

# Configure Google OAuth
auth = GoogleProvider(
    client_id=os.environ["MCP_OIDC_CLIENT_ID"],
    client_secret=os.environ["MCP_OIDC_CLIENT_SECRET"],
    base_url=f"https://{os.environ['MCP_DOMAIN']}",
    allowed_users=[os.environ["MCP_ALLOWED_USERS"]],
)

# Aggregate all MCP servers
config = {
    "mcpServers": {
        "context7": {
            "url": "http://localhost:3100/servers/context7/sse",
            "transport": "http"
        },
        "firecrawl": {
            "url": "http://localhost:3100/servers/firecrawl/sse",
            "transport": "http"
        },
        "linkup": {
            "url": "http://localhost:3100/servers/linkup/sse",
            "transport": "http"
        },
        "openmemory": {
            "url": "http://localhost:3100/servers/openmemory/sse",
            "transport": "http"
        },
        "perplexity": {
            "url": "http://localhost:3100/servers/perplexity/sse",
            "transport": "http"
        }
    }
}

# Create authenticated gateway
gateway = FastMCP.as_proxy(config, name="MCP Gateway", auth=auth)

if __name__ == "__main__":
    gateway.run(transport="http", host="0.0.0.0", port=443)
```

### 2. Update Deployment

- Install FastMCP in Docker image
- Replace mcp-auth-proxy with gateway.py
- Keep mcp-proxy running on localhost:3100 as backend
- Configure production keys/storage per FastMCP docs

### 3. OAuth Configuration

Google OAuth redirect URI:
- Update to FastMCP's callback path (check docs for exact path)
- Likely: `https://mcp.example.com/auth/callback`

### 4. Client Configuration

**TypingMind/Gemini CLI:**
- Server URL: TBD (check FastMCP exposed paths)
- OAuth flow will work natively via DCR
- Each server available with prefix: `context7_*`, `firecrawl_*`, etc.

## References

- [FastMCP Proxy Servers](https://gofastmcp.com/servers/proxy)
- [FastMCP OAuth Proxy](https://gofastmcp.com/servers/auth/oauth-proxy)
- [FastMCP Multi-Server Config](https://gofastmcp.com/servers/proxy#multi-server-configurations)

## Timeline

1. ✅ Identified mcp-auth-proxy limitations
2. ✅ Found FastMCP as proper solution
3. ⏳ Create gateway.py implementation
4. ⏳ Test locally
5. ⏳ Deploy to GCP
6. ⏳ Verify OAuth flow works end-to-end

## Notes

- FastMCP properly handles MCP protocol (stdio, HTTP+SSE, Streamable HTTP)
- Built-in OAuth proxy bridges DCR clients to traditional providers
- Single endpoint serves all aggregated servers
- Production requires Redis/DynamoDB for token storage across instances
