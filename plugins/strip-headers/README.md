# Strip Headers Plugin

Remove all request headers that match specified prefixes before forwarding to upstream services. Useful for removing internal/debug headers that shouldn't reach backend services.

## Configuration

| Parameter                     | Type  | Required | Description                       |
|-------------------------------|-------|----------|-----------------------------------|
| `strip_headers_with_prefixes` | array | Yes      | List of header prefixes to remove |

## Usage

### Remove Internal Headers

```yaml
plugins:
  - name: strip-headers
    config:
      strip_headers_with_prefixes:
        - x-internal-
        - x-debug-
```

### Remove Sensitive Headers

```yaml
plugins:
  - name: strip-headers
    config:
      strip_headers_with_prefixes:
        - x-sensitive-
        - x-private-
        - x-secret-
```

### Remove Gateway Headers

```yaml
plugins:
  - name: strip-headers
    config:
      strip_headers_with_prefixes:
        - x-kong-
        - x-gateway-
        - x-proxy-
```

## Behavior

### Matching

- Headers are matched by **prefix** (case-sensitive)
- All headers starting with any configured prefix are removed
- Multiple prefixes can be specified

### Examples

With config:
```yaml
strip_headers_with_prefixes:
  - x-internal-
  - x-debug-
```

| Incoming Header       | Action  |
|-----------------------|---------|
| `x-internal-user-id`  | Removed |
| `x-internal-trace`    | Removed |
| `x-debug-mode`        | Removed |
| `x-request-id`        | Kept    |
| `authorization`       | Kept    |

### Request Flow

1. Get all headers from incoming request
2. For each header, check if it starts with any configured prefix
3. Remove matching headers from the request to upstream
4. Forward cleaned request to backend service

## Use Cases

- **Security:** Remove internal routing headers before reaching backend
- **Privacy:** Strip debug/trace headers in production
- **Clean Requests:** Remove gateway-specific headers from upstream requests

## Plugin Info

- **Name:** `strip-headers`
- **Priority:** `8000`
- **Version:** `1.0.0`
- **Protocols:** HTTP/HTTPS

