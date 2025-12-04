# Conditional Request Termination Plugin

Terminate requests based on numeric query parameter conditions. Useful for blocking requests that exceed certain thresholds (e.g., pagination limits).

## Configuration

| Parameter              | Type   | Default   | Required | Description                               |
|------------------------|--------|-----------|----------|-------------------------------------------|
| `query_param_key`      | string | `pageNum` | Yes      | Query parameter to evaluate               |
| `operator`             | string | `>`       | No       | Comparison operator: `==`, `>`, `<`       |
| `query_param_value`    | number | `10`      | Yes      | Value to compare against                  |
| `response_status_code` | number | `420`     | Yes      | Status code when condition matches        |
| `response_json`        | string | *(error)* | Yes      | JSON response body when condition matches |

### Default Response JSON

```json
{
  "error": {
    "message": "You can check the list of all the participating teams soon after the match begins.",
    "cause": "Request error",
    "code": "REQUEST_VALIDATION_VIOLATION"
  }
}
```

## Usage

### Block High Page Numbers

```yaml
plugins:
  - name: conditional-req-termination
    config:
      query_param_key: pageNum
      operator: ">"
      query_param_value: 50
      response_status_code: 400
      response_json: '{"error": {"message": "Maximum page limit exceeded", "code": "PAGINATION_ERROR"}}'
```

### Block Specific Values

```yaml
plugins:
  - name: conditional-req-termination
    config:
      query_param_key: limit
      operator: "=="
      query_param_value: 0
      response_status_code: 400
      response_json: '{"error": {"message": "Limit cannot be zero", "code": "VALIDATION_ERROR"}}'
```

### Block Low Values

```yaml
plugins:
  - name: conditional-req-termination
    config:
      query_param_key: page
      operator: "<"
      query_param_value: 1
      response_status_code: 400
      response_json: '{"error": {"message": "Page must be at least 1", "code": "VALIDATION_ERROR"}}'
```

## Behavior

| Operator | Condition                  | Example                    |
|----------|----------------------------|----------------------------|
| `>`      | param > configured value   | `pageNum=51` > `50` → block |
| `<`      | param < configured value   | `page=0` < `1` → block      |
| `==`     | param == configured value  | `limit=0` == `0` → block    |

### Request Flow

1. Extract query parameter specified by `query_param_key`
2. Convert value to number
3. Compare against `query_param_value` using `operator`
4. If condition matches → terminate with `response_status_code` and `response_json`
5. If condition doesn't match → continue to upstream

### Edge Cases

- If query parameter is **missing** → request continues normally
- If query parameter is **non-numeric** → request continues normally
- Response JSON must be valid JSON (validated at configuration time)

## Plugin Info

- **Name:** `conditional-req-termination`
- **Priority:** `8001`
- **Version:** `1.0.0`
- **Protocols:** HTTP/HTTPS

