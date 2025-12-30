# Usage Guide

Common workflows and examples for Ascend Astra Kong Gateway.

---

## Table of Contents

1. [Multi-Tenant API Management](#multi-tenant-api-management)
2. [API Key Authentication](#api-key-authentication)
3. [Rate Limiting](#rate-limiting)
4. [CORS Configuration](#cors-configuration)
5. [Maintenance Mode](#maintenance-mode)
6. [Adding New Services](#adding-new-services)
7. [Common Patterns](#common-patterns)

---

## Multi-Tenant API Management

The tenant-manager plugin provides a complete multi-tenant system.

### Create a Tenant

```bash
curl -X POST http://localhost:8000/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme Corp",
    "contact_email": "admin@acme.com",
    "description": "Main production tenant"
  }'
```

Response:
```json
{
  "data": {
    "tenant_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "Acme Corp",
    "status": "ACTIVE",
    "created_at": "2024-01-15 10:30:00"
  }
}
```

### List All Tenants

```bash
curl http://localhost:8000/v1/tenants
```

Response:
```json
{
  "data": {
    "tenants": [
      {
        "tenant_id": "a1b2c3d4-...",
        "name": "Acme Corp",
        "contact_email": "admin@acme.com"
      }
    ],
    "pagination": {
      "current_page": 1,
      "page_size": 20,
      "total_count": 1
    }
  }
}
```

### Get Tenant Details

```bash
curl http://localhost:8000/v1/tenants/{tenant_id}
```

### Create a Project

```bash
curl -X POST http://localhost:8000/v1/tenants/{tenant_id}/projects \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Production API"
  }'
```

Response (includes auto-generated API key):
```json
{
  "data": {
    "tenant_id": "a1b2c3d4-...",
    "project_id": "p1p2p3p4-...",
    "project_key": "production-api",
    "name": "Production API",
    "status": "ACTIVE",
    "api_key": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "api_key_id": "k1k2k3k4-...",
    "api_key_name": "Production API"
  }
}
```

### List Projects

```bash
curl http://localhost:8000/v1/tenants/{tenant_id}/projects
```

### Generate Additional API Key

```bash
curl -X POST http://localhost:8000/v1/tenants/{tenant_id}/projects/{project_id}/api-keys \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mobile App Key"
  }'
```

### Rotate API Key

```bash
curl -X POST http://localhost:8000/v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate
```

Response:
```json
{
  "data": {
    "key_id": "k1k2k3k4-...",
    "name": "Production API",
    "api_key": "<new-api-key>",
    "rotated_at": "2024-01-15 12:00:00"
  }
}
```

---

## API Key Authentication

Protect your services with API key authentication.

### Enable api-key-auth on a Service

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "api-key-auth",
    "config": {
      "input_header": "x-api-key",
      "output_header": "x-project-key",
      "hide_api_key": true,
      "cache_enabled": true,
      "cache_ttl": 300
    }
  }'
```

### Make Authenticated Requests

```bash
# With valid API key
curl -H "X-Api-Key: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
     http://localhost:8000/api/resource

# Without API key (401 error)
curl http://localhost:8000/api/resource
# {"error":{"code":"AA-1001","message":"Unauthorized"}}
```

### Upstream Headers

When authentication succeeds, the upstream receives:
- `X-Project-Key: <project-key>` - The project key
- `X-Tenant-Id: <uuid>` (if `add_tenant_header: true`)
- `X-Tenant-Name: <name>` (if `add_tenant_header: true`)
- `X-Project-Id: <uuid>` (if `add_project_id_header: true`)

### Allow Anonymous Access

For public endpoints that optionally accept API keys:

```yaml
plugins:
  - name: api-key-auth
    service: my-service
    config:
      anonymous_on_missing: true
```

---

## Rate Limiting

Protect services from abuse with rate limiting.

### Basic Rate Limiting (per service)

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting-v2",
    "config": {
      "limit": 100,
      "period": "minute",
      "policy": "batch-redis",
      "batch_size": 10
    }
  }'
```

### Per-Project Rate Limiting

Limit by project key (from api-key-auth):

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting-v2",
    "config": {
      "limit": 1000,
      "period": "hour",
      "limit_by": "header",
      "header_name": "x-project-key",
      "policy": "batch-redis",
      "batch_size": 10
    }
  }'
```

### Custom Rate Limit Response

```yaml
plugins:
  - name: rate-limiting-v2
    service: my-service
    config:
      limit: 100
      period: minute
      status_code: 429
      content_type: application/json
      body: |
        {
          "error": {
            "code": "RATE_LIMIT_EXCEEDED",
            "message": "Too many requests. Please try again later.",
            "retry_after": 60
          }
        }
```

### Policies Comparison

| Policy | Use Case | Accuracy | Performance |
|--------|----------|----------|-------------|
| `local` | Single node, high performance | Per-node | Fastest |
| `redis` | Multi-node, exact counting | Accurate | Moderate |
| `batch-redis` | Multi-node, balanced | Good | Fast |

---

## CORS Configuration

Enable cross-origin requests for browser applications.

### Global CORS

```bash
curl -X POST http://localhost:8001/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cors",
    "config": {
      "origins": ["https://app.example.com", "https://admin.example.com"],
      "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
      "headers": ["Authorization", "Content-Type", "X-Api-Key"],
      "credentials": true,
      "max_age": 3600
    }
  }'
```

### Development CORS (Allow All)

**Note:** Do not use in production with `credentials: true`

```yaml
plugins:
  - name: cors
    config:
      origins:
        - "*"
      credentials: false
```

### Wildcard Subdomains

Allow all subdomains of a domain:

```yaml
plugins:
  - name: cors
    config:
      origins:
        - "https://*.example.com"
      credentials: true
```

### Preflight Handling

For OPTIONS requests:

```yaml
# Handle preflight in Kong (default)
plugins:
  - name: cors
    config:
      preflight_continue: false

# Forward preflight to upstream
plugins:
  - name: cors
    config:
      preflight_continue: true
```

---

## Maintenance Mode

Enable maintenance mode for planned downtime.

### Enable Global Maintenance

```bash
curl -X POST http://localhost:8001/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintenance",
    "config": {
      "status_code": 503,
      "message": "System maintenance in progress. We will be back shortly.",
      "exclude_paths": ["/health", "/status"]
    }
  }'
```

### Enable for Specific Service

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintenance",
    "config": {
      "status_code": 503,
      "body": "{\"status\": \"maintenance\", \"message\": \"This service is temporarily unavailable\", \"expected_recovery\": \"2024-01-15T15:00:00Z\"}"
    }
  }'
```

### Disable Maintenance

```bash
# Get plugin ID
curl http://localhost:8001/plugins | jq '.data[] | select(.name=="maintenance") | .id'

# Delete plugin
curl -X DELETE http://localhost:8001/plugins/{plugin_id}
```

### Scheduled Maintenance via Config

```yaml
# Disable when done by setting enabled: false
plugins:
  - name: maintenance
    enabled: true  # Change to false when done
    config:
      status_code: 503
      message: "Scheduled maintenance until 15:00 UTC"
```

---

## Adding New Services

### Via Declarative Config (kong.yml)

```yaml
services:
  - name: new-api
    host: api.internal.example.com
    port: 8080
    protocol: http
    connect_timeout: 10000
    read_timeout: 60000
    write_timeout: 60000
    routes:
      - name: new-api-routes
        paths:
          - /api/v2
        methods:
          - GET
          - POST
          - PUT
          - DELETE
        strip_path: false
    plugins:
      - name: api-key-auth
        config:
          hide_api_key: true
      - name: rate-limiting-v2
        config:
          limit: 1000
          period: minute
```

Sync the configuration:
```bash
./scripts/deck-sync.sh
```

### Via Admin API

```bash
# Create service
curl -X POST http://localhost:8001/services \
  -H "Content-Type: application/json" \
  -d '{
    "name": "new-api",
    "url": "http://api.internal.example.com:8080"
  }'

# Create route
curl -X POST http://localhost:8001/services/new-api/routes \
  -H "Content-Type: application/json" \
  -d '{
    "name": "new-api-route",
    "paths": ["/api/v2"],
    "methods": ["GET", "POST", "PUT", "DELETE"]
  }'

# Enable plugins
curl -X POST http://localhost:8001/services/new-api/plugins \
  -H "Content-Type: application/json" \
  -d '{"name": "api-key-auth"}'
```

---

## Common Patterns

### Authenticated API with Rate Limiting

```yaml
services:
  - name: protected-api
    url: http://backend:8080
    routes:
      - paths: [/api]

plugins:
  # Authentication (runs first due to higher priority)
  - name: api-key-auth
    service: protected-api
    config:
      output_header: x-project-key
      add_tenant_header: true

  # Per-project rate limiting
  - name: rate-limiting-v2
    service: protected-api
    config:
      limit_by: header
      header_name: x-project-key
      limit: 1000
      period: minute
```

### Public + Private Endpoints

```yaml
services:
  # Public endpoints (no auth)
  - name: public-api
    url: http://backend:8080
    routes:
      - name: health
        paths: [/health, /status]

  # Private endpoints (auth required)
  - name: private-api
    url: http://backend:8080
    routes:
      - name: api-routes
        paths: [/api]

plugins:
  - name: api-key-auth
    service: private-api
```

### Strip Sensitive Headers

```yaml
plugins:
  - name: strip-headers
    config:
      strip_headers_with_prefixes:
        - x-internal-
        - x-debug-
        - x-forwarded-for
```

### Block High Page Numbers

Prevent expensive database queries:

```yaml
plugins:
  - name: conditional-req-termination
    route: paginated-list
    config:
      query_param_key: page
      operator: ">"
      query_param_value: 100
      response_status_code: 400
      response_json: '{"error": {"message": "Page number exceeds maximum"}}'
```

### Header Transformation Pipeline

```yaml
plugins:
  # 1. Validate API key and set project-key
  - name: api-key-auth
    config:
      input_header: x-api-key
      output_header: x-project-key
      hide_api_key: true

  # 2. Strip any internal headers that shouldn't reach backend
  - name: strip-headers
    config:
      strip_headers_with_prefixes:
        - x-internal-
```

---

## Next Steps

- [Plugin Reference](./PLUGINS.md) - Detailed plugin configuration
- [Configuration Reference](./CONFIGURATION.md) - Environment variables
- [Installation Guide](./INSTALLATION.md) - Setup and deployment

