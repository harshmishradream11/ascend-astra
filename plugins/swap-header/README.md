# Swap Header Plugin

Swap/rename a source header to a target header. The source header is removed and its value is copied to the target header. Returns an error if the source header is missing.

## Configuration

| Parameter       | Type   | Default         | Required | Description                    |
|-----------------|--------|-----------------|----------|--------------------------------|
| `source_header` | string | `x-api-key`     | No       | Header to read the value from  |
| `target_header` | string | `x-project-key` | No       | Header to set the value to     |

## Usage

### Default

```yaml
plugins:
  - name: swap-header
    enabled: true
```

This swaps `x-api-key` → `x-project-key` using defaults.

### Custom Headers

```yaml
plugins:
  - name: swap-header
    config:
      source_header: x-client-token
      target_header: x-auth-token
```

### Authorization Header Swap

```yaml
plugins:
  - name: swap-header
    config:
      source_header: x-external-auth
      target_header: authorization
```

## Behavior

### Success Flow

1. Read value from `source_header`
2. Remove `source_header` from request
3. Set `target_header` with the original value
4. Forward request to upstream

### Error Response

If `source_header` is missing, returns:

```json
{
  "error": {
    "message": "Missing API key in request header",
    "code": "AKPK-1001",
    "cause": "Header 'x-api-key' is not present in the request"
  }
}
```

**Status Code:** `401 Unauthorized`

### Examples

**Request with header:**
```
GET /api/resource
x-api-key: my-secret-key
```

**Forwarded to upstream:**
```
GET /api/resource
x-project-key: my-secret-key
```

## Use Cases

- **Header Normalization:** Convert external header names to internal conventions
- **API Key Transformation:** Rename API key header for backend compatibility
- **Auth Header Mapping:** Map external auth headers to standard formats

## Plugin Info

- **Name:** `swap-header` (internally: `api-key-to-project-key`)
- **Priority:** `1000`
- **Version:** `1.0.0`
- **Protocols:** HTTP/HTTPS

