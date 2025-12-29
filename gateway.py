#!/usr/bin/env python3
"""
FastMCP Gateway with Google OAuth

Aggregates multiple MCP servers and provides OAuth authentication
via Google. Replaces mcp-auth-proxy with proper MCP protocol support.
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
    auth = GoogleProvider(
        client_id=client_id,
        client_secret=client_secret,
        base_url=base_url,
    )
    
    # Aggregate all MCP servers from localhost mcp-proxy
    config = {
        "mcpServers": {
            "context7": {
                "url": "http://localhost:3100/servers/context7/mcp",
                "transport": "http"
            },
            "firecrawl": {
                "url": "http://localhost:3100/servers/firecrawl/mcp",
                "transport": "http"
            },
            "linkup": {
                "url": "http://localhost:3100/servers/linkup/mcp",
                "transport": "http"
            },
            "openmemory": {
                "url": "http://localhost:3100/servers/openmemory/mcp",
                "transport": "http"
            },
            "perplexity": {
                "url": "http://localhost:3100/servers/perplexity/mcp",
                "transport": "http"
            }
        }
    }
    
    # Create authenticated gateway
    print(f"Starting MCP Gateway with Google OAuth")
    print(f"Base URL: {base_url}")
    print(f"Access control: Google OAuth + consent screen")
    print(f"Aggregating {len(config['mcpServers'])} MCP servers")
    
    gateway = FastMCP.as_proxy(config, name="MCP Gateway", auth=auth)
    
    # Always run on port 8000 (Caddy handles HTTPS on 443)
    port = 8000
    print(f"Listening on port {port} (Caddy will proxy HTTPS)")
    
    gateway.run(transport="http", host="0.0.0.0", port=port)

if __name__ == "__main__":
    main()
