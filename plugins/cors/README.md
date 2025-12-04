# CORS Plugin

Handle Cross-Origin Resource Sharing (CORS) for frontend applications. This plugin adds the necessary CORS headers to allow browsers to make cross-origin requests to your API through Kong.

## Configuration

| Parameter            | Type    | Required | Default                                                                          | Description                                                                                           |
|----------------------|---------|----------|----------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `origins`            | array   | Yes      | `["*"]`                                                                          | Allowed origin domains. Use `*` for all, or specific domains. Supports wildcards like `*.example.com` |
| `methods`            | array   | Yes      | `["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]`                   | HTTP methods allowed for CORS requests                                                                |
| `headers`            | array   | No       | `["Accept", "Accept-Language", "Content-Language", "Content-Type", "Authorization", "X-Requested-With", "X-Request-ID"]` | Headers allowed in CORS requests                                                                      |
| `exposed_headers`    | array   | No       | `["X-Request-ID", "X-Kong-Request-Id"]`                                          | Headers exposed to the browser in the response                                                        |
| `credentials`        | boolean | No       | `true`                                                                           | Allow credentials (cookies, auth headers)                                                             |
| `max_age`            | integer | No       | `3600`                                                                           | Preflight response cache duration (seconds)                                                           |
| `preflight_continue` | boolean | No       | `false`                                                                          | Forward preflight requests to upstream                                                                |

## Usage

### Basic Configuration (Allow Specific Frontend)

```yaml
plugins:
  - name: cors
    config:
      origins:
        - https://my-frontend.example.com
        - https://staging.example.com
      credentials: true
```

### Allow Multiple Subdomains

```yaml
plugins:
  - name: cors
    config:
      origins:
        - "*.example.com"
        - "*.staging.example.com"
      credentials: false
```

### Development Mode (Allow All Origins)

> ⚠️ **Warning:** Don't use in production! Credentials must be disabled for wildcard origins.

```yaml
plugins:
  - name: cors
    config:
      origins:
        - "*"
      credentials: false
```

### Restrictive Configuration

```yaml
plugins:
  - name: cors
    config:
      origins:
        - https://app.example.com
      methods:
        - GET
        - POST
      headers:
        - Content-Type
        - Authorization
      exposed_headers:
        - X-Request-ID
      credentials: true
      max_age: 7200
```

### Route-Level Configuration

Apply CORS to specific routes:

```yaml
services:
  - name: api-service
    url: http://backend:8080
    routes:
      - name: api-route
        paths:
          - /api
        plugins:
          - name: cors
            config:
              origins:
                - https://frontend.example.com
```

## Behavior

### Preflight Requests

When a browser makes a "non-simple" request (e.g., with custom headers or methods like PUT/DELETE), it first sends a preflight OPTIONS request:

1. Browser sends `OPTIONS` request with:
   - `Origin` header
   - `Access-Control-Request-Method` header
   - `Access-Control-Request-Headers` header (optional)

2. Plugin responds with:
   - `Access-Control-Allow-Origin`
   - `Access-Control-Allow-Methods`
   - `Access-Control-Allow-Headers`
   - `Access-Control-Max-Age` (caching)
   - `Access-Control-Allow-Credentials` (if enabled)

3. Browser caches response for `max_age` seconds

### Simple Requests

For simple requests (GET/POST with standard headers), the plugin adds CORS headers directly to the response:

- `Access-Control-Allow-Origin`
- `Access-Control-Allow-Credentials` (if enabled)
- `Access-Control-Expose-Headers`
- `Vary: Origin` (for proper caching)

### Origin Matching

| Pattern                    | Matches                                                      |
|----------------------------|--------------------------------------------------------------|
| `*`                        | All origins (cannot use with credentials)                    |
| `https://example.com`      | Exact match only                                             |
| `*.example.com`            | Any subdomain: `app.example.com`, `api.example.com`          |
| `https://*.example.com`    | Any subdomain with https: `https://app.example.com`          |

### Headers Flow

```
Browser                          Kong (CORS Plugin)                    Upstream
   |                                     |                                 |
   |-- OPTIONS (preflight) ------------->|                                 |
   |                                     |-- Check origin allowed          |
   |                                     |-- Return 204 with CORS headers  |
   |<-- 204 + CORS headers --------------|                                 |
   |                                     |                                 |
   |-- GET /api (with Origin) ---------->|                                 |
   |                                     |-- Forward request ------------->|
   |                                     |<-- Response -------------------|
   |                                     |-- Add CORS headers              |
   |<-- Response + CORS headers ---------|                                 |
```

## Common Frontend Scenarios

### React/Vue/Angular App

```yaml
plugins:
  - name: cors
    config:
      origins:
        - http://localhost:3000    # Development
        - https://myapp.com        # Production
      headers:
        - Content-Type
        - Authorization
        - X-Requested-With
      credentials: true
```

### Mobile App with Web View

```yaml
plugins:
  - name: cors
    config:
      origins:
        - https://app.example.com
        - capacitor://localhost    # Capacitor
        - ionic://localhost        # Ionic
      credentials: true
```

### API Gateway for Multiple Frontends

```yaml
plugins:
  - name: cors
    config:
      origins:
        - https://admin.example.com
        - https://user.example.com
        - https://partner.example.com
      methods:
        - GET
        - POST
        - PUT
        - DELETE
      credentials: true
```

## Troubleshooting

### "Origin not allowed" Error

- Check that your frontend's exact origin is in the `origins` list
- Include the protocol (`http://` or `https://`)
- Include the port if non-standard (`http://localhost:3000`)

### Credentials Not Working

- Cannot use `credentials: true` with wildcard (`*`) origin
- Specify exact origins when using credentials

### Preflight Not Cached

- Check `max_age` configuration
- Browser may have caching disabled in dev tools

### Headers Not Exposed

- Add headers to `exposed_headers` for frontend access
- Only headers in this list are accessible via JavaScript

## Plugin Info

- **Name:** `cors`
- **Priority:** `2000`
- **Version:** `1.0.0`
- **Protocols:** HTTP/HTTPS

