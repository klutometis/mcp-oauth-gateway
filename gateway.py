#!/usr/bin/env python3
"""
FastMCP Gateway with Google OAuth

Aggregates multiple MCP servers and provides OAuth authentication
via Google. Uses stdio transport directly to avoid HTTP proxy
performance issues (https://github.com/jlowin/fastmcp/issues/1583).
"""

from fastmcp import FastMCP
from fastmcp.server.auth.providers.google import GoogleProvider
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

def main():
    # Load .env file if it exists (looks for .env, .env.local, etc.)
    if Path(".env.local").exists():
        print("Loading environment from .env.local")
        load_dotenv(".env.local")
    elif Path(".env").exists():
        print("Loading environment from .env")
        load_dotenv(".env")
    
    # Get configuration from environment
    client_id = os.environ.get("MCP_OIDC_CLIENT_ID")
    client_secret = os.environ.get("MCP_OIDC_CLIENT_SECRET")
    domain = os.environ.get("MCP_DOMAIN")
    
    # Validate required environment variables
    missing = []
    if not client_id:
        missing.append("MCP_OIDC_CLIENT_ID")
    if not client_secret:
        missing.append("MCP_OIDC_CLIENT_SECRET")
    if not domain:
        missing.append("MCP_DOMAIN")
    
    if missing:
        print(f"Error: Missing required environment variables: {', '.join(missing)}", file=sys.stderr)
        print("\nCreate a .env or .env.local file", file=sys.stderr)
        print("See .env.example for template", file=sys.stderr)
        sys.exit(1)
    
    # Determine base URL (handle both localhost and production)
    if domain.startswith("http://") or domain.startswith("https://"):
        base_url = domain
    elif domain.startswith("localhost"):
        base_url = f"http://{domain}"
    else:
        base_url = f"https://{domain}"
    
    # Configure Google OAuth
    # Explicitly request email scope from Google so we can validate user email
    # This is passed to Google's authorization endpoint
    auth = GoogleProvider(
        client_id=client_id,
        client_secret=client_secret,
        base_url=base_url,
        extra_authorize_params={
            "access_type": "offline",
            "prompt": "consent",
            "scope": "openid email",  # Request email from Google
        },
    )
    
    # Aggregate all MCP servers using stdio transport (fast!)
    # Pass API keys from environment to each server
    config = {
        "mcpServers": {
            "context7": {
                "command": "npx",
                "args": ["-y", "@upstash/context7-mcp"],
                "transport": "stdio",
                "env": {
                    "CONTEXT7_API_KEY": os.environ.get("CONTEXT7_API_KEY")
                }
            },
            "firecrawl": {
                "command": "npx",
                "args": ["-y", "firecrawl-mcp"],
                "transport": "stdio",
                "env": {
                    "FIRECRAWL_API_KEY": os.environ.get("FIRECRAWL_API_KEY")
                }
            },
            "linkup": {
                "command": "npx",
                "args": [
                    "-y",
                    "linkup-mcp-server",
                    f"apiKey={os.environ.get('LINKUP_API_KEY')}"
                ],
                "transport": "stdio"
            },
            "openmemory": {
                "command": "npx",
                "args": ["-y", "openmemory"],
                "transport": "stdio",
                "env": {
                    "CLIENT_NAME": "openmemory",
                    "OPENMEMORY_API_KEY": os.environ.get("OPENMEMORY_API_KEY")
                }
            },
            "perplexity": {
                "command": "npx",
                "args": ["-y", "perplexity-mcp"],
                "transport": "stdio",
                "env": {
                    "PERPLEXITY_API_KEY": os.environ.get("PERPLEXITY_API_KEY")
                }
            }
        }
    }
    
    # Create authenticated gateway
    print(f"Starting MCP Gateway with Google OAuth")
    print(f"Base URL: {base_url}")
    print(f"Access control: Google OAuth + consent screen")
    print(f"Aggregating {len(config['mcpServers'])} MCP servers via stdio (fast!)")
    
    gateway = FastMCP.as_proxy(config, name="MCP Gateway", auth=auth)
    
    # Set up middleware and static pages
    from starlette.responses import FileResponse
    from starlette.routing import Route
    from starlette.middleware.base import BaseHTTPMiddleware
    
    static_dir = Path(__file__).parent / "static"
    
    # Middleware to check allowed users after OAuth authentication
    # Must be added via http_app middleware parameter to run in correct order
    allowed_users_env = os.environ.get("MCP_ALLOWED_USERS", "")
    allowed_users = set(email.strip().lower() for email in allowed_users_env.split(",") if email.strip())
    
    middlewares = []
    if allowed_users:
        class AuthCheckMiddleware:
            """Pure ASGI middleware to check user email after authentication."""
            def __init__(self, app):
                self.app = app
            
            async def __call__(self, scope, receive, send):
                # Only check HTTP requests to /mcp
                if scope["type"] == "http" and scope["path"].startswith("/mcp"):
                    # User is set by AuthenticationMiddleware in the ASGI stack
                    user = scope.get("user")
                    
                    # Extract email from authenticated user's access token
                    user_email = ""
                    if user and hasattr(user, "access_token"):
                        access_token = user.access_token
                        email = access_token.claims.get("email")
                        user_email = email.lower() if email else ""
                    
                    # Block if email not in allowed list
                    if allowed_users and user_email and user_email not in allowed_users:
                        print(f"Access denied for {user_email}", file=sys.stderr)
                        import json
                        body = json.dumps({"error": "Access denied", "message": f"User {user_email} is not authorized"}).encode()
                        await send({
                            "type": "http.response.start",
                            "status": 403,
                            "headers": [[b"content-type", b"application/json"], [b"content-length", str(len(body)).encode()]],
                        })
                        await send({"type": "http.response.body", "body": body})
                        return
                    elif allowed_users and not user_email:
                        print(f"WARNING: Could not extract email from authenticated user", file=sys.stderr)
                
                await self.app(scope, receive, send)
        
        from starlette.middleware import Middleware
        middlewares.append(Middleware(AuthCheckMiddleware))
        print(f"Email restriction enabled for: {', '.join(allowed_users)}")
    else:
        print("WARNING: MCP_ALLOWED_USERS not set - any Google account can authenticate!", file=sys.stderr)
    
    # Get the HTTP app with our middleware
    app = gateway.http_app(middleware=middlewares)
    
    # Add static page routes
    async def serve_privacy(request):
        return FileResponse(static_dir / "privacy.html")
    
    async def serve_terms(request):
        return FileResponse(static_dir / "terms.html")
    
    # Insert static routes for /privacy and /terms
    app.router.routes.insert(0, Route("/privacy", endpoint=serve_privacy, methods=["GET"], name="privacy"))
    app.router.routes.insert(0, Route("/terms", endpoint=serve_terms, methods=["GET"], name="terms"))
    
    # Wrap with home page middleware
    class HomePageMiddleware:
        """Pure ASGI middleware to serve home page at /"""
        def __init__(self, app):
            self.app = app
        
        async def __call__(self, scope, receive, send):
            # Serve home page for GET / (browser requests)
            if scope["type"] == "http" and scope["method"] == "GET" and scope["path"] == "/":
                from starlette.responses import FileResponse
                response = FileResponse(static_dir / "index.html")
                await response(scope, receive, send)
                return
            await self.app(scope, receive, send)
    
    app = HomePageMiddleware(app)
    
    print(f"Serving static pages: / (via middleware), /privacy, /terms")
    print(f"OAuth endpoints: /.well-known/*, /register")
    print(f"MCP protocol: /mcp/*")
    
    # Always run on port 8000 (Caddy handles HTTPS on 443)
    port = 8000
    print(f"Listening on port {port} (Caddy will proxy HTTPS)")
    
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
    main()
