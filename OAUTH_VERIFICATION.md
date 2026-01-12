# Google OAuth Verification Requirements

This document outlines the requirements for submitting the MCP Gateway OAuth app for external verification with Google.

## Overview

External verification allows the OAuth app to have longer-lasting sessions and removes the "unverified app" warning for users. Without verification, sessions expire more frequently and users see security warnings.

Reference: [Google OAuth 2.0 Policy Compliance](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance)

## Requirements Checklist

### 1. Separate Projects for Testing and Production ✓

- [x] Use separate Google Cloud projects for testing and production OAuth clients
- [x] Production project must not contain test environments or localhost URIs

### 2. Project Contacts ✓

- [x] Ensure project has up-to-date Owner/Editor roles in [IAM Console](https://console.developers.google.com/iam-admin/iam)
- [x] Google will send notifications to these accounts about verification status

### 3. Accurate Identity ✓

Configure branding in [OAuth Consent Screen](https://console.developers.google.com/auth/branding):

- [x] App name: "MCP Gateway" (or your preferred name)
- [ ] App logo (optional but recommended)
- [x] Must accurately represent the application's identity

### 4. Request Only Needed Scopes ✓

- [x] Review scopes requested in OAuth consent screen
- [x] Request minimal scopes necessary for functionality
- [x] Remove any example/debug scopes from development

### 5. Domain Ownership ✓

**Critical requirement**: All domains must be verified in [Google Search Console](https://search.google.com/search-console/about)

Domains to verify:
- [ ] Home page domain (e.g., `mcp-gateway.example.com`)
- [ ] Redirect URI domains (if different from home page)
- [ ] Privacy policy domain (if different from home page)
- [ ] Terms of service domain (if different from home page)

**Steps to verify domain:**
1. Go to [Google Search Console](https://search.google.com/search-console/about)
2. Add property for your domain
3. Follow verification steps (DNS TXT record, HTML file upload, or HTML meta tag)
4. Use a Google account that's an Owner/Editor of the OAuth project

### 6. Home Page ✓

**Status**: Implemented in `/static/index.html`

Requirements:
- [x] Publicly accessible home page on verified domain
- [x] Description of app functionality
- [x] Links to privacy policy and terms of service
- [x] Exists on verified domain under your ownership

**URL**: `https://your-domain.com/` (served by gateway.py:119-139)

### 7. Privacy Policy ✓

**Status**: Implemented in `/static/privacy.html`

Requirements:
- [x] Publicly accessible privacy policy
- [x] Describes data collection and usage
- [x] Explains how user data is shared with third parties
- [x] Describes data retention and security practices
- [x] Lists user rights (access, deletion, etc.)

**URL**: `https://your-domain.com/privacy`

### 8. Terms of Service ✓

**Status**: Implemented in `/static/terms.html`

Requirements:
- [x] Optional but recommended for production apps
- [x] Describes service usage terms
- [x] Disclaimers and liability limitations

**URL**: `https://your-domain.com/terms`

### 9. Secure Redirect URIs ✓

- [x] All redirect URIs use HTTPS (not HTTP)
- [x] Handled by Caddy reverse proxy in production
- [x] No localhost URIs in production OAuth client

### 10. Sensitive/Restricted Scopes

If using sensitive or restricted scopes:
- [ ] Submit scopes for verification before requesting in production
- [ ] May require security assessment depending on scopes
- [ ] Review [additional requirements](https://developers.google.com/terms/api-services-user-data-policy#additional_requirements_for_specific_api_scopes)

## Implementation Details

### Static Pages Served by Gateway

The gateway.py uses middleware to serve the home page and adds static routes for privacy/terms:

```python
# gateway.py:117-156
# Middleware to intercept GET / and serve home page
class HomePageMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # Serve home page for GET / (browser requests)
        if request.method == "GET" and request.url.path == "/":
            return FileResponse(static_dir / "index.html")
        # Everything else goes through normal routing
        return await call_next(request)

# Insert static routes for /privacy and /terms
static_routes = [
    Route("/privacy", endpoint=serve_privacy, methods=["GET"], name="privacy"),
    Route("/terms", endpoint=serve_terms, methods=["GET"], name="terms"),
]
app.routes = static_routes + list(app.routes)

# Add middleware to serve home page at /
app.add_middleware(HomePageMiddleware)
```

**Technical approach**: 
- Home page at `/` is served via middleware to avoid conflicts with OAuth routes (`/.well-known/*`, `/register`)
- Middleware intercepts only `GET /` requests (browser traffic) and serves the home page
- OAuth and MCP protocol requests pass through to normal routing
- `/privacy` and `/terms` are added as regular routes
- No breaking changes to existing endpoints

### Docker Build

Static files are copied into Docker image:

```dockerfile
# Dockerfile:29
COPY static/ ./static/
```

### Testing

Test static pages and MCP endpoint locally:

```bash
./test-local.sh
# Will output HTTP status codes for /, /privacy, /terms
# And test OAuth discovery endpoint
```

Visit in browser:
- **Static pages**: http://localhost:8000/, http://localhost:8000/privacy, http://localhost:8000/terms
- **MCP endpoint**: http://localhost:8000/mcp/* (unchanged)
- **OAuth discovery**: http://localhost:8000/.well-known/oauth-authorization-server

Connect with MCP clients (unchanged):
```bash
npx @modelcontextprotocol/inspector http://localhost:8000
npx github:tilesprivacy/mcp-cli http://localhost:8000
```

## Submission Process

Once all requirements are met:

1. **Configure OAuth Consent Screen**
   - Go to [Branding page](https://console.developers.google.com/auth/branding)
   - Fill in all required fields:
     - App name
     - User support email
     - Home page URL: `https://your-domain.com/`
     - Privacy policy URL: `https://your-domain.com/privacy`
     - Terms of service URL: `https://your-domain.com/terms` (optional)
     - Authorized domains: List all domains used

2. **Verify Domain Ownership**
   - Complete domain verification in Google Search Console
   - Ensure the Google account verifying domains has Owner/Editor role in OAuth project

3. **Submit for Brand Verification**
   - Follow [brand verification guide](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification)
   - May take several days to weeks for review
   - Google will email project owners/editors with status updates

4. **Monitor Verification Status**
   - Check status in [OAuth Consent Screen](https://console.developers.google.com/auth/branding)
   - Respond promptly to any Google requests for additional information

## Timeline

- **Domain verification**: Usually immediate (after DNS/file verification)
- **Brand verification**: 3-7 business days (typical)
- **Security assessment** (if needed for restricted scopes): 2-6 weeks

## Common Issues

### Domain Verification Fails

- Ensure DNS records have propagated (check with `dig` or `nslookup`)
- Try alternative verification methods (HTML file, meta tag)
- Use the exact domain format (with or without www)

### Verification Rejected

- Review rejection reasons in email from Google
- Common issues:
  - Privacy policy doesn't adequately describe data usage
  - App name doesn't match actual functionality
  - Domains not properly verified
  - Test URIs included in production OAuth client

### Scopes Require Security Assessment

Some scopes require third-party security assessment:
- Review [scope requirements](https://developers.google.com/terms/api-services-user-data-policy#additional_requirements_for_specific_api_scopes)
- Consider using less sensitive scopes if possible
- Budget 4-8 weeks for assessment process

## Resources

- [OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies)
- [Policy Compliance Guide](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance)
- [Brand Verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification)
- [User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)
- [Google Search Console](https://search.google.com/search-console/about)
- [OAuth Consent Screen](https://console.developers.google.com/auth/branding)
