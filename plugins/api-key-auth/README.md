# API Key Auth Plugin

This Kong plugin validates API keys against the tenant-manager database and transforms the request headers for upstream services.

## Flow

```
Client Request                                    Upstream Request
─────────────────                                ─────────────────
x-api-key: 550e8400-e29b-41d4-a716-446655440000  →  x-project-key: my-project-key
x-user-id: 12345                                     x-user-id: 12345
```

## How It Works

1. **Extracts** the API key (UUID) from the `x-api-key` header (configurable)
2. **Validates** against the `api_keys` table in the database
3. **Checks** that the API key, project, and tenant are all ACTIVE
4. **Replaces** the `x-api-key` header with `x-project-key` containing the project_key
5. **Updates** the `last_used_at` timestamp on the API key

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `input_header` | `x-api-key` | Header name containing the API key |
| `output_header` | `x-project-key` | Header name to set with project key |
| `hide_api_key` | `true` | Remove the API key header before forwarding |
| `add_tenant_header` | `false` | Add `x-tenant-id` and `x-tenant-name` headers |
| `add_project_id_header` | `false` | Add `x-project-id` header |
| `anonymous_on_missing` | `false` | Allow requests without API key |

## Usage

### Global Plugin (all routes)

```yaml
plugins:
  - name: api-key-auth
    enabled: true
    config:
      input_header: "x-api-key"
      output_header: "x-project-key"
      hide_api_key: true
```

### Route-specific Plugin

```yaml
routes:
  - name: my-api-route
    paths:
      - /v1/allocations
    plugins:
      - name: api-key-auth
        config:
          input_header: "x-api-key"
          output_header: "x-project-key"
          hide_api_key: true
          add_tenant_header: true
```

## Example

### Create a tenant, project, and API key

```bash
# Create tenant
curl -X POST http://localhost:8000/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"name": "my-tenant", "contact_email": "admin@example.com"}'

# Response: {"data": {"tenant_id": "abc-123", ...}}

# Create project
curl -X POST http://localhost:8000/v1/tenants/abc-123/projects \
  -H "Content-Type: application/json" \
  -d '{"name": "My Project", "project_key": "test_project_key"}'

# Response: {"data": {"project_id": "def-456", ...}}

# Generate API key
curl -X POST http://localhost:8000/v1/tenants/abc-123/projects/def-456/api-keys \
  -H "Content-Type: application/json" \
  -d '{"name": "Production Key"}'

# Response: {"data": {"api_key": "550e8400-e29b-41d4-a716-446655440000", ...}}
```

### Use the API key

```bash
# Request with API key (UUID format)
curl http://localhost:8000/v1/allocations \
  -H "x-api-key: 550e8400-e29b-41d4-a716-446655440000" \
  -H "x-user-id: USER_ID"

# Upstream receives:
#   x-project-key: test_project_key
#   x-user-id: USER_ID
#   (x-api-key is removed)
```

## Error Responses

| Code | HTTP Status | Message |
|------|-------------|---------|
| AKA-1001 | 401 | API key is required |
| AKA-1002 | 401 | Invalid API key |
| AKA-1003 | 401 | API key is inactive/revoked |
| AKA-1004 | 500 | Database error |
| AKA-1006 | 401 | Tenant is inactive |
| AKA-1007 | 401 | Project is inactive |

## Context Data

The plugin stores validated key data in `kong.ctx.shared.api_key_auth` for use by other plugins:

```lua
{
    api_key_id = "uuid",
    project_id = "uuid",
    project_key = "test_project_key",
    project_name = "My Project",
    tenant_id = "uuid",
    tenant_name = "my-tenant",
}
```

