# Plugin Reference

Complete configuration reference for all custom plugins in Ascend Astra.

---

## Table of Contents

1. [maintenance](#1-maintenance)
2. [conditional-req-termination](#2-conditional-req-termination)
3. [strip-headers](#3-strip-headers)
4. [cors](#4-cors)
5. [api-key-auth](#5-api-key-auth)
6. [swap-header](#6-swap-header)
7. [rate-limiting-v2](#7-rate-limiting-v2)
8. [tenant-manager](#8-tenant-manager)
9. [Installation](#installation)
10. [Troubleshooting](#troubleshooting)

---

## 1. maintenance

Block all traffic with configurable maintenance responses.

### Purpose

Enable maintenance mode for services or routes, returning a custom maintenance message to all requests.

### Supported Phases

- `access`

### Priority

`11000` (runs very early in request lifecycle)

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `status_code` | integer | No | `400` | HTTP status code (100-599) |
| `message` | string | No | - | Simple message (cannot be used with `body`) |
| `content_type` | string | No | `application/json` | Content-Type header for response |
| `body` | string | No | *(see below)* | Full response body |
| `exclude_paths` | array[string] | No | `["/kong-healthcheck"]` | Paths to exclude from maintenance |

**Default body:**
```json
{
  "error": {
    "MsgCode": "MG1008",
    "MsgShowUp": "Popup",
    "MsgText": "Ascend is temporarily unavailable due to scheduled system maintenance. We'll be up & running shortly",
    "MsgTitle": "We are Under Maintenance",
    "MsgType": "Error"
  }
}
```

### Validation Rules

- `message` cannot be used together with `content_type` or `body`
- `content_type` requires a `body` to be set

### Enable via Admin API

```bash
# Enable globally
curl -X POST http://localhost:8001/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintenance",
    "config": {
      "status_code": 503,
      "message": "Service is under maintenance",
      "exclude_paths": ["/health", "/kong-healthcheck"]
    }
  }'

# Enable for a specific service
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintenance",
    "config": {
      "status_code": 503,
      "body": "{\"status\": \"maintenance\", \"retry_after\": 3600}"
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: maintenance
    enabled: true
    config:
      status_code: 503
      message: "Service under maintenance"
      exclude_paths:
        - /health
        - /kong-healthcheck
    service: my-service
```

### Example Request

```bash
# Request during maintenance
curl -i http://localhost:8000/api/resource

# HTTP/1.1 400 Bad Request
# Content-Type: application/json
# {"error":{"MsgCode":"MG1008","MsgTitle":"We are Under Maintenance",...}}
```

---

## 2. conditional-req-termination

Terminate requests based on query parameter conditions.

### Purpose

Block requests when specific query parameters match configured conditions. Useful for rate limiting by parameter value or blocking certain request patterns.

### Supported Phases

- `access`

### Priority

`8001`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `query_param_key` | string | Yes | `pageNum` | Query parameter to check |
| `operator` | string | No | `>` | Comparison operator: `==`, `>`, `<` |
| `query_param_value` | number | Yes | `10` | Value to compare against |
| `response_status_code` | number | Yes | `420` | HTTP status to return on match |
| `response_json` | string | Yes | *(see below)* | JSON response body |

**Default response_json:**
```json
{
  "error": {
    "message": "You can check the list of all the participating teams soon after the match begins.",
    "cause": "Request error",
    "code": "REQUEST_VALIDATION_VIOLATION"
  }
}
```

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "conditional-req-termination",
    "config": {
      "query_param_key": "pageNum",
      "operator": ">",
      "query_param_value": 50,
      "response_status_code": 400,
      "response_json": "{\"error\": {\"message\": \"Page number too high\", \"code\": \"INVALID_PAGE\"}}"
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: conditional-req-termination
    service: my-service
    config:
      query_param_key: pageNum
      operator: ">"
      query_param_value: 50
      response_status_code: 400
      response_json: '{"error": {"message": "Page number too high"}}'
```

### Example Behavior

```bash
# Allowed request (pageNum <= 50)
curl "http://localhost:8000/api/list?pageNum=10"
# → Request passes through

# Blocked request (pageNum > 50)
curl "http://localhost:8000/api/list?pageNum=100"
# → HTTP 400: {"error": {"message": "Page number too high"}}
```

---

## 3. strip-headers

Remove request headers matching specified prefixes.

### Purpose

Strip sensitive or internal headers before forwarding to upstream services. Useful for security hardening.

### Supported Phases

- `access`

### Priority

`8000`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `strip_headers_with_prefixes` | array[string] | Yes | - | List of header prefixes to remove |

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "strip-headers",
    "config": {
      "strip_headers_with_prefixes": ["x-internal-", "x-debug-", "x-trace-"]
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: strip-headers
    service: my-service
    config:
      strip_headers_with_prefixes:
        - x-internal-
        - x-debug-
        - x-trace-
```

### Example Behavior

```bash
# Request with internal headers
curl -H "X-Internal-User: admin" \
     -H "X-Debug-Mode: true" \
     -H "X-Custom-Header: value" \
     http://localhost:8000/api/resource

# Upstream receives only:
# X-Custom-Header: value
# (x-internal-* and x-debug-* headers are stripped)
```

---

## 4. cors

Handle Cross-Origin Resource Sharing (CORS) with wildcard subdomain support.

### Purpose

Manage CORS preflight and response headers with support for:
- Wildcard origins (`*`)
- Specific origins
- Wildcard subdomains (`*.example.com`)
- Credentials support

### Supported Phases

- `access` (preflight handling)
- `header_filter` (response headers)

### Priority

`2000`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `origins` | array[string] | Yes | `["*"]` | Allowed origins. Supports `*`, specific domains, and `*.domain.com` |
| `methods` | array[string] | Yes | `["GET","POST","PUT","PATCH","DELETE","OPTIONS","HEAD"]` | Allowed HTTP methods |
| `headers` | array[string] | No | *(see below)* | Allowed request headers |
| `exposed_headers` | array[string] | No | `["X-Request-ID", "X-Kong-Request-Id"]` | Headers exposed to browser |
| `credentials` | boolean | No | `true` | Allow credentials (cookies, auth headers) |
| `max_age` | integer | No | `3600` | Preflight cache duration (seconds) |
| `preflight_continue` | boolean | No | `false` | Forward OPTIONS to upstream |

**Default headers:**
```
Accept, Accept-Language, Content-Language, Content-Type, Authorization, X-Requested-With, X-Request-ID
```

### Validation Rules

- `credentials: true` cannot be used with wildcard (`*`) origin

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cors",
    "config": {
      "origins": ["https://app.example.com", "https://*.example.com"],
      "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
      "headers": ["Authorization", "Content-Type", "X-Api-Key"],
      "exposed_headers": ["X-Request-ID"],
      "credentials": true,
      "max_age": 7200
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: cors
    enabled: true
    config:
      origins:
        - http://localhost:5173
        - https://app.example.com
      methods:
        - GET
        - POST
        - PUT
        - DELETE
        - OPTIONS
      headers:
        - Accept
        - Authorization
        - Content-Type
        - X-Api-Key
      exposed_headers:
        - X-Request-ID
      credentials: true
      max_age: 3600
```

### Example Preflight Response

```bash
curl -i -X OPTIONS http://localhost:8000/api/resource \
  -H "Origin: https://app.example.com" \
  -H "Access-Control-Request-Method: POST"

# HTTP/1.1 204 No Content
# Access-Control-Allow-Origin: https://app.example.com
# Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
# Access-Control-Allow-Headers: Authorization, Content-Type
# Access-Control-Allow-Credentials: true
# Access-Control-Max-Age: 3600
```

---

## 5. api-key-auth

Validate API keys against database with Redis caching.

### Purpose

Authenticate requests using API keys stored in the tenant-manager database. Validates:
- API key existence and status
- Associated project status
- Associated tenant status

### Supported Phases

- `access`

### Priority

`1100`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `input_header` | string | No | `x-api-key` | Header containing API key |
| `output_header` | string | No | `x-project-key` | Header to set with project key |
| `hide_api_key` | boolean | No | `true` | Remove API key header from upstream request |
| `add_tenant_header` | boolean | No | `false` | Add `x-tenant-id` and `x-tenant-name` headers |
| `add_project_id_header` | boolean | No | `false` | Add `x-project-id` header |
| `anonymous_on_missing` | boolean | No | `false` | Allow requests without API key |
| `cache_enabled` | boolean | No | `true` | Enable Redis caching |
| `cache_ttl` | integer | No | `300` | Cache TTL in seconds |
| `redis_host` | string | No | `redis` | Redis host |
| `redis_port` | integer | No | `6379` | Redis port |
| `redis_timeout` | integer | No | `2000` | Redis timeout (ms) |
| `redis_prefix` | string | No | `api_key_auth:` | Redis key prefix |

### Error Codes

| Code | Description |
|------|-------------|
| `AA-1001` | Missing API key |
| `AA-1002` | Invalid API key |
| `AA-1003` | Expired/inactive API key |
| `AA-1004` | Database error |
| `AA-1005` | Project not found |
| `AA-1006` | Tenant inactive |
| `AA-1007` | Project inactive |

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "api-key-auth",
    "config": {
      "input_header": "x-api-key",
      "output_header": "x-project-key",
      "hide_api_key": true,
      "add_tenant_header": true,
      "cache_enabled": true,
      "cache_ttl": 300,
      "redis_host": "redis",
      "redis_port": 6379
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: api-key-auth
    service: my-service
    config:
      input_header: x-api-key
      output_header: x-project-key
      hide_api_key: true
      add_tenant_header: false
      add_project_id_header: false
      anonymous_on_missing: false
      cache_enabled: true
      cache_ttl: 300
      redis_host: redis
      redis_port: 6379
      redis_prefix: 'api_key_auth:'
      redis_timeout: 2000
```

### Example Behavior

```bash
# Successful authentication
curl -H "X-Api-Key: abc12345-1234-5678-9012-123456789012" \
     http://localhost:8000/api/resource
# → Upstream receives: X-Project-Key: my-project-key

# Missing API key
curl http://localhost:8000/api/resource
# → HTTP 401: {"error":{"code":"AA-1001","message":"Unauthorized"}}

# Invalid API key
curl -H "X-Api-Key: invalid-key" http://localhost:8000/api/resource
# → HTTP 401: {"error":{"code":"AA-1002","message":"Unauthorized"}}
```

---

## 6. swap-header

Rename/swap one request header to another.

### Purpose

Copy the value from a source header to a target header, removing the source header. Useful for header normalization.

### Supported Phases

- `access`

### Priority

`1000`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `source_header` | string | No | `x-api-key` | Header to read from |
| `target_header` | string | No | `x-project-key` | Header to write to |

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "swap-header",
    "config": {
      "source_header": "x-api-key",
      "target_header": "x-project-key"
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: swap-header
    service: my-service
    config:
      source_header: x-api-key
      target_header: x-project-key
```

### Example Behavior

```bash
# Request with source header
curl -H "X-Api-Key: my-key" http://localhost:8000/api/resource

# Upstream receives:
# X-Project-Key: my-key
# (X-Api-Key header is removed)
```

### Error Response

If the source header is missing:
```json
{
  "error": {
    "message": "Missing API key in request header",
    "code": "SH-1001",
    "cause": "Header 'x-api-key' is not present in the request"
  }
}
```

---

## 7. rate-limiting-v2

Advanced rate limiting with multiple algorithms and Redis support.

### Purpose

Implement rate limiting with:
- Fixed-window and leaky-bucket algorithms
- Local, Redis, and batch-Redis policies
- Per-service or per-header limiting

### Supported Phases

- `access` (counter increment)
- `log` (leaky bucket decrement)

### Priority

`960`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `algorithm` | string | No | `fixed-window` | Algorithm: `fixed-window`, `leaky-bucket` |
| `period` | string | No | `minute` | Time window: `second`, `minute`, `hour`, `day` |
| `limit` | number | Yes | - | Max requests per period |
| `limit_by` | string | No | `service` | Limit scope: `service`, `header` |
| `header_name` | string | Conditional | - | Header for `limit_by: header` |
| `policy` | string | No | `batch-redis` | Storage: `local`, `redis`, `batch-redis` |
| `batch_size` | integer | Conditional | `10` | Batch size for `batch-redis` |
| `status_code` | integer | No | `429` | Rate limit response status |
| `content_type` | string | No | `application/json` | Response Content-Type |
| `body` | string | No | `{"message": "API rate limit exceeded"}` | Rate limit response body |
| `redis_write_timeout` | integer | No | `10` | Redis write timeout (ms) |
| `redis_read_timeout` | integer | No | `10` | Redis read timeout (ms) |
| `redis_connect_timeout` | integer | No | `10` | Redis connect timeout (ms) |

### Conditional Requirements

- `batch_size` is required when `policy: batch-redis`
- `header_name` is required when `limit_by: header`
- `policy` is required when `algorithm: fixed-window`

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting-v2",
    "config": {
      "algorithm": "fixed-window",
      "period": "minute",
      "limit": 100,
      "limit_by": "header",
      "header_name": "x-project-key",
      "policy": "batch-redis",
      "batch_size": 10,
      "status_code": 429,
      "body": "{\"error\": \"Rate limit exceeded\"}"
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: rate-limiting-v2
    service: my-service
    config:
      algorithm: fixed-window
      period: minute
      limit: 1000
      limit_by: service
      policy: batch-redis
      batch_size: 10
      status_code: 429
      content_type: application/json
      body: '{"message": "API rate limit exceeded"}'
```

### Example Behavior

```bash
# Normal request (within limit)
curl http://localhost:8000/api/resource
# → Request passes through

# Rate limited request
curl http://localhost:8000/api/resource
# → HTTP 429: {"message": "API rate limit exceeded"}
```

---

## 8. tenant-manager

Multi-tenant management REST API implemented as a Kong plugin.

### Purpose

Provides a complete tenant management system with:
- Tenant CRUD operations
- Project management per tenant
- API key generation and rotation
- Database-backed storage via Kong migrations

### Supported Phases

- `access`

### Priority

`900`

### Configuration Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `api_path_prefix` | string | No | `/v1` | Base path for API endpoints |
| `default_page_size` | integer | No | `20` | Default pagination size |
| `max_page_size` | integer | No | `100` | Maximum pagination size |

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/tenants` | Create tenant |
| `GET` | `/v1/tenants` | List tenants |
| `GET` | `/v1/tenants/{tenant_id}` | Get tenant details |
| `POST` | `/v1/tenants/{tenant_id}/projects` | Create project |
| `GET` | `/v1/tenants/{tenant_id}/projects` | List projects |
| `GET` | `/v1/tenants/{tenant_id}/projects/{project_id}` | Get project details |
| `POST` | `/v1/tenants/{tenant_id}/projects/{project_id}/api-keys` | Generate API key |
| `GET` | `/v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}` | Get API key metadata |
| `POST` | `/v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate` | Rotate API key |

### Database Tables

This plugin creates these tables via migrations:
- `tenants` - Tenant information
- `projects` - Projects per tenant
- `api_keys` - API keys per project

### Enable via Admin API

```bash
curl -X POST http://localhost:8001/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tenant-manager",
    "config": {
      "api_path_prefix": "/v1",
      "default_page_size": 20,
      "max_page_size": 100
    }
  }'
```

### Enable via Declarative Config (kong.yml)

```yaml
plugins:
  - name: tenant-manager
    enabled: true
    config:
      api_path_prefix: /v1
      default_page_size: 20
      max_page_size: 100
```

### Example Usage

```bash
# Create a tenant
curl -X POST http://localhost:8000/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Company",
    "contact_email": "admin@mycompany.com",
    "description": "Main tenant"
  }'

# Response:
# {
#   "data": {
#     "tenant_id": "abc12345-...",
#     "name": "My Company",
#     "status": "ACTIVE",
#     "created_at": "2024-01-01 00:00:00"
#   }
# }

# Create a project
curl -X POST http://localhost:8000/v1/tenants/{tenant_id}/projects \
  -H "Content-Type: application/json" \
  -d '{"name": "Production API"}'

# Response includes auto-generated API key:
# {
#   "data": {
#     "project_id": "xyz789...",
#     "project_key": "production-api",
#     "api_key": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
#     ...
#   }
# }

# Rotate API key
curl -X POST http://localhost:8000/v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate

# Response:
# {
#   "data": {
#     "key_id": "...",
#     "api_key": "<new-api-key>",
#     "rotated_at": "2024-01-01 12:00:00"
#   }
# }
```

---

## Installation

### Via Docker (Recommended)

Plugins are automatically installed when building the Docker image:

```dockerfile
# From Dockerfile
COPY plugins/maintenance /usr/local/share/lua/5.1/kong/plugins/maintenance
COPY plugins/cors /usr/local/share/lua/5.1/kong/plugins/cors
# ... other plugins
```

### Manual Installation

1. Copy plugin files to Kong's plugin directory:
```bash
cp -r plugins/maintenance /usr/local/share/lua/5.1/kong/plugins/
```

2. Add plugin to `KONG_PLUGINS` environment variable:
```bash
export KONG_PLUGINS=bundled,maintenance,cors,api-key-auth,...
```

3. Restart Kong:
```bash
kong restart
```

### Via LuaRocks (for development)

```bash
# Install from local rockspec
cd ascend-astra
luarocks make kong.rockspec
```

---

## Troubleshooting

### Plugin Not Loading

**Symptoms:** Plugin not appearing in `/plugins` endpoint, "plugin not found" errors

**Solutions:**
1. Verify plugin is in `KONG_PLUGINS` environment variable
2. Check plugin files exist in `/usr/local/share/lua/5.1/kong/plugins/<name>/`
3. Verify `handler.lua` and `schema.lua` exist
4. Check Kong error logs: `docker compose logs kong | grep -i error`

### Configuration Errors

**Symptoms:** "schema violation" errors when enabling plugin

**Solutions:**
1. Verify all required fields are provided
2. Check field types match schema (string vs integer)
3. Validate conditional requirements (e.g., `header_name` with `limit_by: header`)
4. Use Kong Admin API to get detailed validation errors:
```bash
curl -s http://localhost:8001/schemas/plugins/rate-limiting-v2 | jq
```

### Redis Connection Issues

**Symptoms:** Rate limiting or caching not working, timeout errors in logs

**Solutions:**
1. Verify Redis is running: `docker compose ps redis`
2. Test Redis connectivity: `redis-cli -h localhost -p 8079 ping`
3. Check Redis configuration matches plugin config
4. Review Redis logs: `docker compose logs redis`

### Database Errors (tenant-manager, api-key-auth)

**Symptoms:** "database error" responses, migration failures

**Solutions:**
1. Check PostgreSQL is running: `docker compose ps postgres`
2. Verify migrations ran successfully: `docker compose logs kong-migrations`
3. Connect to database and verify tables exist:
```bash
docker compose exec postgres psql -U kong -d kong -c "\dt"
```

### Log Inspection

```bash
# All Kong logs
docker compose logs kong

# Filter for errors
docker compose logs kong 2>&1 | grep -i error

# Follow logs in real-time
docker compose logs -f kong

# Plugin-specific debug
# Add to kong.conf or environment:
# KONG_LOG_LEVEL=debug
```

### Common Error Codes

| Plugin | Code | Meaning |
|--------|------|---------|
| api-key-auth | AA-1001 | Missing API key header |
| api-key-auth | AA-1002 | Invalid API key |
| api-key-auth | AA-1003 | Expired/inactive API key |
| swap-header | SH-1001 | Missing source header |
| tenant-manager | TM-1001 | Validation error |
| tenant-manager | TM-1002 | Resource not found |
| tenant-manager | TM-1003 | Duplicate resource |
| tenant-manager | TM-1004 | Database error |

