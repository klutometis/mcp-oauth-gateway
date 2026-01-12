# Changelog

## 2026-01-12 - Email-Based Access Control

### Added
- **Email-based user access control**: Gateway now restricts access to specific Google accounts
  - Set `MCP_ALLOWED_USERS` environment variable with comma-separated email addresses
  - Example: `MCP_ALLOWED_USERS=bob@example.com,alice@example.com`
  - Users not in the list receive 403 Forbidden with clear error message
- Custom ASGI middleware (`AuthCheckMiddleware`) to validate user email after OAuth authentication
- Explicit email scope request in Google OAuth flow to ensure email is available in token claims

### Changed
- GoogleProvider now requests `openid email` scopes from Google (via `extra_authorize_params`)
- Updated `deploy-gateway.sh` to pass `MCP_ALLOWED_USERS` to container
- Updated `test-local.sh` to pass `MCP_ALLOWED_USERS` to container
- Added `pyjwt>=2.10.1` dependency (initially for JWT decoding attempt, kept for future use)

### Technical Details
- Middleware integrates into FastMCP's Starlette middleware stack via `gateway.http_app(middleware=[...])`
- Runs AFTER `AuthenticationMiddleware` populates `scope["user"]` with `AuthenticatedUser` object
- Extracts email from `user.access_token.claims["email"]` (populated by GoogleProvider's userinfo fetch)
- Only checks `/mcp/*` requests (OAuth flow endpoints remain unrestricted)
- Logs access denials to stderr: `Access denied for <email>`

### Security
- Public OAuth verification is maintained (no 15-minute timeout)
- Access control enforced at application layer after successful OAuth authentication
- Users can authenticate but are blocked from using MCP tools if not in allowed list

## 2026-01-11 - OAuth Verification Support

### Added
- Static HTML pages for Google OAuth verification requirements:
  - `/` - Home page describing MCP Gateway and integrated services
  - `/privacy` - Privacy policy covering data collection, usage, and user rights
  - `/terms` - Terms of service with usage terms and disclaimers
- Comprehensive documentation in `OAUTH_VERIFICATION.md` covering all Google OAuth compliance requirements
- Enhanced `test-local.sh` to verify static pages return HTTP 200

### Changed
- Updated `Dockerfile` to include `static/` directory in builds
- Added `uvicorn>=0.40.0` to dependencies in `pyproject.toml`
- Gateway now uses `uvicorn.run()` directly to serve custom route-enhanced app

### Technical Details
- Home page at `/` served via Starlette middleware (intercepts GET / only)
- `/privacy` and `/terms` added as static routes
- OAuth endpoints (`/.well-known/*`, `/register`) remain at root and work normally
- MCP protocol endpoints unchanged (still at `/mcp/*`)
- No breaking changes to existing client configurations

### Verification Success
- Successfully submitted and verified with Google OAuth
- Status: "Your branding has been verified and is being shown to users"
- Verification removed 15-minute session timeout (was forcing re-auth every 15min)
