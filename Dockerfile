FROM python:3.12-slim

# Install system dependencies and Caddy
RUN apt-get update && apt-get install -y \
    curl \
    debian-keyring \
    debian-archive-keyring \
    apt-transport-https \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (for npm-based MCP servers)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install uv for Python package management
RUN pip install --no-cache-dir uv

# Set working directory
WORKDIR /app

# Copy project files
COPY pyproject.toml .
COPY servers.json .
COPY gateway.py .

# Install dependencies with uv
RUN uv sync

# Install mcp-proxy
RUN uv pip install mcp-proxy

# Copy Caddy configuration and entrypoint
COPY Caddyfile /app/Caddyfile
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Expose HTTP and HTTPS ports
EXPOSE 80
EXPOSE 443

# Run the entrypoint
CMD ["./entrypoint.sh"]
