# Rate Limiting V2 Plugin

Advanced rate limiting plugin with support for Redis-based counters and multiple algorithms. Built on top of Kong's rate-limiting plugin with enhanced features.

## Configuration

| Parameter              | Type    | Default                                  | Required | Description                                     |
|------------------------|---------|------------------------------------------|----------|-------------------------------------------------|
| `algorithm`            | string  | `fixed-window`                           | No       | Algorithm: `fixed-window` or `leaky-bucket`     |
| `period`               | string  | `minute`                                 | No       | Time period: `second`, `minute`, `hour`, `day`  |
| `limit`                | number  | —                                        | Yes      | Maximum requests allowed per period             |
| `limit_by`             | string  | `service`                                | No       | Limit by: `service` or `header`                 |
| `header_name`          | string  | —                                        | *        | Header name (required when `limit_by: header`)  |
| `policy`               | string  | `batch-redis`                            | No       | Storage: `redis`, `batch-redis`, `local`        |
| `batch_size`           | integer | `10`                                     | *        | Batch size (required for `batch-redis`)         |
| `status_code`          | integer | `429`                                    | Yes      | Response status when limit exceeded             |
| `content_type`         | string  | `application/json`                       | Yes      | Response content type                           |
| `body`                 | string  | `{"message": "API rate limit exceeded"}` | Yes      | Response body when limit exceeded               |
| `redis_write_timeout`  | integer | `10`                                     | No       | Redis write timeout (ms)                        |
| `redis_read_timeout`   | integer | `10`                                     | No       | Redis read timeout (ms)                         |
| `redis_connect_timeout`| integer | `10`                                     | No       | Redis connection timeout (ms)                   |

## Algorithms

### Fixed Window

Counts requests in fixed time windows (e.g., every minute from :00 to :59).

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      algorithm: fixed-window
      period: minute
      limit: 100
      policy: batch-redis
```

### Leaky Bucket

Smooths traffic by processing requests at a steady rate, with automatic counter adjustment after each request.

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      algorithm: leaky-bucket
      period: minute
      limit: 100
```

## Storage Policies

| Policy        | Description                                           |
|---------------|-------------------------------------------------------|
| `local`       | In-memory storage (per worker, not shared)            |
| `redis`       | Direct Redis storage (accurate, higher latency)       |
| `batch-redis` | Batched Redis updates (optimized performance)         |

## Usage

### Service-Level Rate Limiting

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      limit: 1000
      period: minute
      limit_by: service
      policy: batch-redis
      batch_size: 10
```

### Header-Based Rate Limiting

Rate limit per unique header value (e.g., per API key):

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      limit: 100
      period: minute
      limit_by: header
      header_name: x-project-key
      policy: batch-redis
```

### Strict Rate Limiting

For accurate counting with lower throughput:

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      limit: 50
      period: second
      policy: redis
      algorithm: fixed-window
```

### Custom Error Response

```yaml
plugins:
  - name: rate-limiting-v2
    config:
      limit: 100
      period: minute
      status_code: 429
      content_type: application/json
      body: '{"error": {"code": "RATE_LIMITED", "message": "Too many requests"}}'
```

## Behavior

### Request Flow

1. Extract identifier (service ID or header value)
2. Increment counter in storage
3. Check if limit exceeded
4. If exceeded → return error response
5. If allowed → continue to upstream

### Metrics

The plugin sets metrics in `kong.ctx.shared.logger_metrics`:

| Metric                | Description                    |
|-----------------------|--------------------------------|
| `rate_limit.allowed`  | Request was allowed            |
| `rate_limit.dropped`  | Request was rate limited       |
| `rate_limiting.error` | Error occurred during limiting |

### Error Handling

- If identifier cannot be found → request continues (logged as error)
- If Redis fails → request continues (logged as error)
- Errors are tracked via metrics for monitoring

## Conditional Requirements

| Condition              | Required Field |
|------------------------|----------------|
| `policy: batch-redis`  | `batch_size`   |
| `limit_by: header`     | `header_name`  |
| `algorithm: fixed-window` | `policy`    |

## Plugin Info

- **Name:** `rate-limiting-v2`
- **Priority:** `960`
- **Version:** `1.0.0`
- **Protocols:** HTTP/HTTPS

## Reference

For more details on rate limiting concepts, see: [Kong Rate Limiting Documentation](https://docs.konghq.com/hub/kong-inc/rate-limiting/)
