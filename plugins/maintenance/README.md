# Maintenance Plugin

Enable maintenance mode to block all traffic with a customizable response. Specific paths can be excluded from maintenance mode.

## Configuration

| Parameter       | Type    | Default                | Required | Description                            |
|-----------------|---------|------------------------|----------|----------------------------------------|
| `status_code`   | integer | `400`                  | No       | HTTP status code to return (100-599)   |
| `message`       | string  | —                      | No       | Simple message response                |
| `content_type`  | string  | `application/json`     | No       | Response content type                  |
| `body`          | string  | *(maintenance JSON)*   | No       | Custom response body                   |
| `exclude_paths` | array   | `["/kong-healthcheck"]`| No       | Paths to exclude from maintenance mode |

### Default Response Body

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

## Validation Rules

- `message` cannot be used together with `content_type` or `body`
- `content_type` requires a `body` to be set

## Usage

### Basic Maintenance Mode

```yaml
plugins:
  - name: maintenance
    enabled: true
```

### Custom Response

```yaml
plugins:
  - name: maintenance
    config:
      status_code: 503
      body: '{"error": "Service under maintenance", "retry_after": 3600}'
      content_type: application/json
```

### With Excluded Paths

```yaml
plugins:
  - name: maintenance
    config:
      status_code: 503
      message: "Service temporarily unavailable"
      exclude_paths:
        - /health
        - /ready
        - /metrics
```

## Behavior

1. When enabled, blocks **all** incoming requests
2. Requests matching paths in `exclude_paths` are allowed through
3. Returns configured `status_code` and response body/message
4. Health check endpoints should be added to `exclude_paths`

## Plugin Info

- **Name:** `maintenance`
- **Priority:** `11000`
- **Version:** `2.0.1`
- **Protocols:** HTTP/HTTPS

