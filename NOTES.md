# MCP OAuth Gateway - Development Notes

## 2026-01-04: Solution - FastMCP with stdio Transport (SUCCESSFUL!)

### Problem Recap

We experienced severe performance issues with FastMCP.as_proxy():
- 30-60 second response times
- Timeouts with concurrent requests
- Root cause: Double HTTP proxying (FastMCP → mcp-proxy → MCP servers)

### Solution That Worked

**Use FastMCP.as_proxy() with stdio transport directly**, bypassing the HTTP proxy layer entirely.

**Before (slow):**
```
Client → FastMCP (HTTP) → mcp-proxy (HTTP) → stdio MCP servers
        ↑ 300-400ms per tool call due to double HTTP proxy
```

**After (fast):**
```
Client → FastMCP → stdio MCP servers directly
        ↑ ~3ms per tool call, handles concurrency beautifully!
```

### Implementation

Changed `gateway.py` to use stdio configuration directly from `servers.json`:

```python
config = {
    "mcpServers": {
        "context7": {
            "command": "npx",
            "args": ["-y", "@upstash/context7-mcp"],
            "transport": "stdio"  # ← Key change: stdio instead of HTTP URL
        },
        "firecrawl": {
            "command": "npx",
            "args": ["-y", "firecrawl-mcp"],
            "transport": "stdio"
        },
        # ... etc for all servers
    }
}

gateway = FastMCP.as_proxy(config, name="MCP Gateway", auth=auth)
gateway.run(transport="http", host="0.0.0.0", port=8000)
```

### Results

✅ **OAuth working** - Google OAuth with DCR support  
✅ **Fast** - Handles multiple concurrent requests efficiently  
✅ **Simple** - Single gateway aggregating all servers  
✅ **Production-ready** - Deployed at `https://mcp.example.com`

### Architecture

**Production:**
```
Internet (443) → Caddy (HTTPS termination) → FastMCP gateway (8000) → stdio MCP servers
```

**Local testing:**
```
localhost:8000 → FastMCP gateway → stdio MCP servers (no Caddy needed)
```

### Key Lessons

1. **HTTP proxying is slow** - FastMCP + HTTP servers = 100-200x slowdown (documented in [Issue #1583](https://github.com/jlowin/fastmcp/issues/1583))
2. **stdio proxying is fast** - FastMCP + stdio servers = ~3ms per call, same as direct
3. **No need for mcp-proxy** - FastMCP can aggregate stdio servers directly
4. **Caddy needed for HTTPS** - FastMCP doesn't handle TLS, use reverse proxy
5. **Set MCP_DOMAIN correctly** - Must be actual domain, not `mcp.example.com`

---

## 2025-12-29: Architecture Decision - Multiple mcp-auth-proxy Instances vs FastMCP Gateway (ABANDONED)

### Problem Discovered

After deploying the FastMCP-based OAuth gateway, we experienced severe performance issues:
- 30-60 second response times per request
- Timeouts with concurrent requests
- Requests appeared to be serialized rather than parallelized

**Root cause:** `FastMCP.as_proxy()` has documented concurrency issues (see [Issue #1583](https://github.com/jlowin/fastmcp/issues/1583)). The architecture was:

```
Client → FastMCP Gateway (as_proxy) → mcp-proxy (3100) → Individual MCP servers
```

This created **two layers of proxying**, compounding the concurrency problems.

### Solution: Per-Server mcp-auth-proxy Instances

Instead of aggregating servers behind a single gateway, deploy separate [mcp-auth-proxy](https://github.com/sigbit/mcp-auth-proxy) instances for each MCP server.

**Architecture:**
```
Client → mcp-auth-proxy (per server) → Individual MCP server
```

**Key advantages:**
- ✅ **No FastMCP bottleneck** - Written in Go, handles streaming properly
- ✅ **Per-server isolation** - One slow server doesn't block others
- ✅ **True concurrency** - Each server handles its own connections independently
- ✅ **Battle-tested** - mcp-auth-proxy is designed for this use case
- ✅ **Supports all transports** - stdio, SSE, HTTP (converts stdio to HTTP automatically)

### Deployment Strategy

**Single VM with wildcard DNS:**

Run 5 mcp-auth-proxy instances on different ports:

```bash
# context7 on port 8001
mcp-auth-proxy --external-url https://context7.mcp.example.com \
  --port 8001 --tls-cert-file /certs/cert.pem --tls-key-file /certs/key.pem \
  --oidc-provider google \
  --oidc-client-id $MCP_OIDC_CLIENT_ID \
  --oidc-client-secret $MCP_OIDC_CLIENT_SECRET \
  -- npx -y @upstash/context7-mcp

# firecrawl on port 8002
mcp-auth-proxy --external-url https://firecrawl.mcp.example.com \
  --port 8002 --tls-cert-file /certs/cert.pem --tls-key-file /certs/key.pem \
  --oidc-provider google \
  --oidc-client-id $MCP_OIDC_CLIENT_ID \
  --oidc-client-secret $MCP_OIDC_CLIENT_SECRET \
  -- npx -y firecrawl-mcp

# linkup on port 8003
mcp-auth-proxy --external-url https://linkup.mcp.example.com \
  --port 8003 --tls-cert-file /certs/cert.pem --tls-key-file /certs/key.pem \
  --oidc-provider google \
  --oidc-client-id $MCP_OIDC_CLIENT_ID \
  --oidc-client-secret $MCP_OIDC_CLIENT_SECRET \
  -- uvx mcp-search-linkup

# openmemory on port 8004
mcp-auth-proxy --external-url https://openmemory.mcp.example.com \
  --port 8004 --tls-cert-file /certs/cert.pem --tls-key-file /certs/key.pem \
  --oidc-provider google \
  --oidc-client-id $MCP_OIDC_CLIENT_ID \
  --oidc-client-secret $MCP_OIDC_CLIENT_SECRET \
  -- npx -y openmemory

# perplexity on port 8005
mcp-auth-proxy --external-url https://perplexity.mcp.example.com \
  --port 8005 --tls-cert-file /certs/cert.pem --tls-key-file /certs/key.pem \
  --oidc-provider google \
  --oidc-client-id $MCP_OIDC_CLIENT_ID \
  --oidc-client-secret $MCP_OIDC_CLIENT_SECRET \
  -- npx -y perplexity-mcp
```

**Caddy configuration with wildcard DNS:**
```caddyfile
*.mcp.example.com {
    @context7 host context7.mcp.example.com
    handle @context7 {
        reverse_proxy localhost:8001
    }
    
    @firecrawl host firecrawl.mcp.example.com
    handle @firecrawl {
        reverse_proxy localhost:8002
    }
    
    @linkup host linkup.mcp.example.com
    handle @linkup {
        reverse_proxy localhost:8003
    }
    
    @openmemory host openmemory.mcp.example.com
    handle @openmemory {
        reverse_proxy localhost:8004
    }
    
    @perplexity host perplexity.mcp.example.com
    handle @perplexity {
        reverse_proxy localhost:8005
    }
}
```

**DNS setup (one-time configuration):**
```
*.mcp.example.com → A record → VM IP
```

This single wildcard DNS entry matches all subdomains (context7, firecrawl, linkup, etc.). Caddy handles routing to the correct port based on the hostname.

### Why Subdomain-Based Routing?

We use **subdomain-based routing** (`context7.mcp.example.com/mcp`) rather than path-based routing (`mcp.example.com/context7/mcp`). While both work with Caddy, subdomain-based has significant advantages for our multi-instance architecture:

**Advantages of subdomain-based:**
- ✅ **True service isolation** - Each service is independent at the DNS level
- ✅ **Easier to scale** - Can move services to different VMs later by just changing DNS
- ✅ **Wildcard SSL certificate** - Single cert covers all services (`*.mcp.example.com`)
- ✅ **Cleaner OAuth redirects** - Each mcp-auth-proxy instance "owns" its domain
- ✅ **Better logs/monitoring** - Hostname identifies the service immediately
- ✅ **Flexible per-service config** - Each subdomain can have different Caddy settings
- ✅ **Security** - Cookies/sessions don't leak between services by default
- ✅ **Matches mcp-auth-proxy expectations** - Designed to own a domain for callbacks

**Disadvantages of path-based:**
- ❌ **OAuth complications** - mcp-auth-proxy expects to control the full domain for callbacks
- ❌ **Path stripping required** - Caddy needs to rewrite paths before proxying
- ❌ **Harder to scale** - All services tied to one domain
- ❌ **Less flexible** - Shared base domain limits per-service configuration
- ❌ **Complex if services move** - Can't just change DNS, need to reconfigure Caddy

With wildcard DNS, subdomain-based routing is just as easy to set up as path-based, with far better long-term benefits.

### Client Configuration

MCP clients (Gemini CLI, etc.) need to configure 5 separate servers instead of 1:

```json
{
  "mcpServers": {
    "context7": {
      "url": "https://context7.mcp.example.com/mcp",
      "transport": "http",
      "auth": "oauth"
    },
    "firecrawl": {
      "url": "https://firecrawl.mcp.example.com/mcp",
      "transport": "http",
      "auth": "oauth"
    },
    "linkup": {
      "url": "https://linkup.mcp.example.com/mcp",
      "transport": "http",
      "auth": "oauth"
    },
    "openmemory": {
      "url": "https://openmemory.mcp.example.com/mcp",
      "transport": "http",
      "auth": "oauth"
    },
    "perplexity": {
      "url": "https://perplexity.mcp.example.com/mcp",
      "transport": "http",
      "auth": "oauth"
    }
  }
}
```

### Tradeoffs

**Pros:**
- Much faster (no proxy bottleneck)
- Better concurrency
- Per-server isolation (one failing server doesn't affect others)
- Simpler architecture (less abstraction layers)
- Same infrastructure cost (one VM)

**Cons:**
- Multiple URLs to configure in clients (one-time setup)
- Multiple DNS entries (one-time setup)
- More processes to manage (can be automated with Docker Compose or systemd)

**Verdict:** The one-time configuration overhead is worth the performance and reliability gains.

### Alternative Considered: FastMCP as Thin OAuth Layer

We considered keeping FastMCP but removing `.as_proxy()` to just handle OAuth, then forward raw HTTP to mcp-proxy. However:
- Would still have two layers of abstraction
- FastMCP's HTTP forwarding without MCP protocol translation is non-trivial
- mcp-auth-proxy already solves this problem elegantly

### Why Not MCP Gateway?

MCP Gateway is designed for **aggregation and catalog integration** of many MCP servers. Our use case is simpler: **add OAuth to existing servers**. The comparison:

- **mcp-auth-proxy**: Lightweight OAuth wrapper for individual servers
- **MCP Gateway**: Centralized orchestration hub for many servers with policies, auditing, catalog integration

For our needs (5 servers, OAuth only), mcp-auth-proxy is the right tool.

### Next Steps

1. Build new deployment script for multi-instance mcp-auth-proxy setup
2. Update Caddyfile for wildcard DNS routing
3. Configure DNS entries for each subdomain
4. Test with one server, then roll out to all five
5. Update client configurations once tested

---

## Initial Implementation (FastMCP-based)

This repository originally implemented a FastMCP-based gateway that aggregated multiple MCP servers behind a single OAuth endpoint. While functionally correct, it suffered from concurrency limitations in `FastMCP.as_proxy()`.

**Key insight from debugging:** The `servers.json` configuration for mcp-proxy must NOT include `"env"` blocks. With `--pass-environment`, mcp-proxy automatically passes all environment variables to child processes. Adding explicit `"env": { "API_KEY": "${API_KEY}" }` blocks breaks this, as the shell variable expansion doesn't happen.

**Correct configuration:**
```json
{
  "mcpServers": {
    "linkup": {
      "command": "uvx",
      "args": ["mcp-search-linkup"],
      "transportType": "stdio"
      // NO env block - --pass-environment handles it
    }
  }
}
```

---

## 2026-01-03: Local Testing of mcp-auth-proxy with OAuth

### Problem: mcp-auth-proxy uses non-standard OAuth paths

Testing mcp-auth-proxy locally revealed that it does **NOT** implement standard OAuth 2.0/2.1 (RFC 6749) paths. This causes issues with generic OAuth clients like MCP Inspector.

#### Standard OAuth 2.0/2.1 paths:
- Authorization endpoint: `/oauth/authorize` or `/authorize`
- Token endpoint: `/oauth/token` or `/token`
- Callback: Application-specific (you tell the OAuth server where to redirect)

#### What mcp-auth-proxy actually uses:
- **Authorization initiation**: `/.auth/<provider>` (e.g., `/.auth/google`)
- **Token endpoint**: `/.idp/token`
- **Discovery endpoint**: `/.idp/auth` (advertised in `/.well-known/oauth-authorization-server`)
- **Callback**: `/.auth/<provider>/callback` (e.g., `/.auth/google/callback`)

#### Why this matters:

1. **Generic OAuth clients fail**: Tools like MCP Inspector expect standard paths (`/oauth/*`)
2. **Discovery endpoints are misleading**: `/.well-known/oauth-authorization-server` claims the authorization endpoint is `/.idp/auth`, but you actually need to use `/.auth/google` (provider-specific)
3. **Provider-specific paths required**: You can't use generic OAuth flows - you must know which provider you're using and go to that provider's specific path

#### Testing process:

**Local setup:**
```bash
./bin/mcp-auth-proxy \
  --external-url http://localhost:8000 \
  --listen :8000 \
  --google-client-id "$MCP_OIDC_CLIENT_ID" \
  --google-client-secret "$MCP_OIDC_CLIENT_SECRET" \
  --google-allowed-users "$MCP_ALLOWED_USERS" \
  -- npx -y @upstash/context7-mcp
```

**What worked:**
1. Open browser to: `http://localhost:8000/.auth/google`
2. Gets redirected to Google OAuth
3. After authenticating, redirected back to: `http://localhost:8000/.auth/google/callback?code=...&state=...`
4. Session cookie is set
5. Can now make authenticated requests

**What didn't work:**
- ❌ `/oauth/authorize` → 401 Unauthorized
- ❌ `/oauth/token` → 401 Unauthorized
- ❌ MCP Inspector (expects standard OAuth paths)
- ❌ Trying to manually construct OAuth URLs (state parameter mismatch)

**Google OAuth Console configuration:**
- **Authorized redirect URIs**: `http://localhost:8000/.auth/google/callback`
  - Note: Must include the `.` before `auth` and `/google` before `/callback`
  - NOT `/auth/callback` or `/oauth/callback`

#### Important gotchas:

1. **State parameter validation**: Don't copy/paste OAuth URLs - the `state` parameter is tied to your session cookie. Let the browser follow redirects naturally.
2. **New browser session**: If you get "invalid OAuth state" errors, open a new incognito/private window and start the flow fresh
3. **Redirect URI must match exactly**: Even small differences (missing `.` or `/google`) will cause `redirect_uri_mismatch` errors

#### Implications for deployment:

- MCP Inspector won't work out-of-the-box with mcp-auth-proxy
- Generic OAuth clients expecting RFC 6749 compliance won't work
- Need to use clients that understand mcp-auth-proxy's custom paths:
  - Gemini CLI (has built-in support)
  - Custom clients that know about `/.auth/<provider>` paths

#### Testing with MCP Inspector (partial solution):

If you want to use MCP Inspector, you need to configure:
- **Authorization endpoint**: `http://localhost:8000/.idp/auth`
- **Token endpoint**: `http://localhost:8000/.idp/token`
- **Redirect URI**: Whatever port MCP Inspector runs on (e.g., `http://localhost:6274/oauth/callback`)

However, this may still not work due to the provider-specific path requirements.

#### Recommendation:

For local testing, use:
1. **Browser-based flow**: Just open `http://localhost:8000/.auth/google` to verify OAuth works
2. **Gemini CLI**: These have native support for mcp-auth-proxy's OAuth implementation
3. **Session cookies**: After authenticating in browser, extract the session cookie for API testing

Don't rely on generic OAuth testing tools - mcp-auth-proxy has a custom implementation.
