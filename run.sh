#!/bin/bash
# Set project-specific variables and run gateway
# Assumes dot-env-secrets is already loaded in your shell environment

set -e

# Override domain for local development
export MCP_DOMAIN="localhost:8000"

# Run the command passed as arguments, or default to gateway
if [[ $# -eq 0 ]]; then
    uv run python gateway.py
else
    "$@"
fi
