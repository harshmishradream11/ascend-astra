# Configuration Reference

Environment variables, configuration files, and security settings for Ascend Astra.

---

## Table of Contents

1. [Environment Variables](#environment-variables)
2. [Docker Compose Configuration](#docker-compose-configuration)
3. [Kong Configuration](#kong-configuration)
4. [Redis Configuration](#redis-configuration)
5. [PostgreSQL Configuration](#postgresql-configuration)
6. [Declarative Configuration (kong.yml)](#declarative-configuration-kongyml)
7. [Security Considerations](#security-considerations)
8. [Production Deployment](#production-deployment)

---

## Environment Variables

### Kong Gateway

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_DATABASE` | `postgres` | Database type |
| `KONG_PG_HOST` | `postgres` | PostgreSQL host |
| `KONG_PG_PORT` | `5432` | PostgreSQL port |
| `KONG_PG_USER` | `kong` | PostgreSQL username |
| `KONG_PG_PASSWORD` | `kongpass` | PostgreSQL password |
| `KONG_PG_DATABASE` | `kong` | PostgreSQL database name |
| `KONG_ADMIN_LISTEN` | `0.0.0.0:8001` | Admin API listen address |
| `KONG_PROXY_LISTEN` | `0.0.0.0:8000` | Proxy listen address |
| `KONG_ADMIN_GUI_URL` | `http://localhost:8002` | Kong Manager URL |
| `KONG_PLUGINS` | *(see below)* | Enabled plugins list |
| `KONG_LOG_LEVEL` | `notice` | Log level |
| `KONG_PROXY_ACCESS_LOG` | `/dev/stdout` | Access log location |
| `KONG_PROXY_ERROR_LOG` | `/dev/stderr` | Error log location |

**KONG_PLUGINS default:**
```
bundled,cors,maintenance,conditional-req-termination,strip-headers,rate-limiting-v2,api-key-auth,tenant-manager,circuit-breaker,host-interpolate-by-header,advanced-router,swap-header
```

### Redis Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_REDIS_HOST` | `redis` | Redis hostname |
| `KONG_REDIS_PORT` | `6379` | Redis port |

### Tenant Seeding

| Variable | Default | Description |
|----------|---------|-------------|
| `SEED_DEFAULT_TENANT` | `true` | Create default tenant on startup |
| `DEFAULT_TENANT_NAME` | `default` | Default tenant name |
| `DEFAULT_TENANT_EMAIL` | `admin@ascend.local` | Default tenant email |
| `DEFAULT_PROJECT_NAME` | `My First Project` | Default project name |
| `DEFAULT_PROJECT_KEY` | `my-first-project` | Default project key |

---

## Docker Compose Configuration

### File: `docker-compose.yml`

```yaml
services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kongpass      # Change in production!
      POSTGRES_DB: kong
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "8032:5432"                     # External port mapping

  # Redis Cache
  redis:
    image: redis:7-alpine
    ports:
      - "8079:6379"                     # External port mapping

  # Kong Gateway
  kong:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"                     # Proxy
      - "8001:8001"                     # Admin API
      - "8002:8002"                     # Kong Manager
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: postgres
      KONG_PG_PASSWORD: kongpass        # Change in production!
      KONG_PLUGINS: bundled,cors,...
    volumes:
      - ./ascend-astra/kong.yml:/kong-config/kong.yml:ro
```

### Port Mappings

| Service | Internal | External | Purpose |
|---------|----------|----------|---------|
| Kong Proxy | 8000 | 8000 | API Gateway |
| Kong Admin | 8001 | 8001 | Administration |
| Kong Manager | 8002 | 8002 | Web UI |
| Kong SSL Proxy | 8443 | 8043 | HTTPS |
| Kong SSL Admin | 8444 | 8044 | HTTPS Admin |
| PostgreSQL | 5432 | 8032 | Database |
| Redis | 6379 | 8079 | Cache |

---

## Kong Configuration

### Dockerfile

The custom Kong image is built with:

```dockerfile
FROM kong:3.7.1-ubuntu

# Install deck CLI
RUN curl -sL https://github.com/kong/deck/releases/download/v1.40.2/deck_1.40.2_linux_amd64.tar.gz ...

# Install LuaRocks dependencies
RUN luarocks install kong-circuit-breaker 2.1.1 --server=https://rocks.konghq.com && \
    luarocks install host-interpolate-by-header 1.3.0 --server=https://rocks.konghq.com && \
    luarocks install kong-advanced-router 0.2.1 --server=https://rocks.konghq.com

# Copy custom plugins
COPY plugins/maintenance /usr/local/share/lua/5.1/kong/plugins/maintenance
COPY plugins/cors /usr/local/share/lua/5.1/kong/plugins/cors
# ... other plugins
```

### Plugin Installation Paths

```
/usr/local/share/lua/5.1/kong/plugins/
├── api-key-auth/
│   ├── handler.lua
│   └── schema.lua
├── cors/
├── maintenance/
├── rate-limiting-v2/
│   ├── handler.lua
│   ├── schema.lua
│   ├── algorithms.lua
│   ├── connections.lua
│   ├── expiration.lua
│   ├── policies.lua
│   └── utils.lua
├── strip-headers/
├── swap-header/
├── conditional-req-termination/
└── tenant-manager/
    ├── handler.lua
    ├── schema.lua
    ├── tenants.lua
    ├── projects.lua
    ├── api_keys.lua
    ├── utils.lua
    └── migrations/
```

---

## Redis Configuration

### Connection Settings

Redis is used by:
- `rate-limiting-v2` plugin for counters
- `api-key-auth` plugin for API key caching

### Plugin Redis Configuration

```yaml
plugins:
  - name: api-key-auth
    config:
      redis_host: redis
      redis_port: 6379
      redis_timeout: 2000
      redis_prefix: "api_key_auth:"
      cache_ttl: 300

  - name: rate-limiting-v2
    config:
      policy: batch-redis
      redis_connect_timeout: 10
      redis_read_timeout: 10
      redis_write_timeout: 10
```

### Redis Key Patterns

| Plugin | Key Pattern |
|--------|-------------|
| api-key-auth | `api_key_auth:<api-key>` |
| rate-limiting-v2 | `ratelimit:<route>:<service>:<identifier>:<timestamp>:<period>` |

---

## PostgreSQL Configuration

### Database Initialization

The `docker/init-db.sql` file runs on first startup:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

### Tables Created by Migrations

Kong migrations create these tables for tenant-manager:

| Table | Purpose |
|-------|---------|
| `tenants` | Tenant accounts |
| `projects` | Projects per tenant |
| `api_keys` | API keys per project |

Plus Kong's internal tables for services, routes, plugins, etc.

### Connection String

```
postgres://kong:kongpass@postgres:5432/kong
```

---

## Declarative Configuration (kong.yml)

### File Location

```
ascend-astra/kong.yml
```

### Format Version

```yaml
_format_version: "3.0"
```

### Structure

```yaml
_format_version: "3.0"

# Global plugins
plugins:
  - name: cors
    enabled: true
    config:
      origins: ["*"]

# Services and routes
services:
  - name: my-service
    host: backend
    port: 8080
    routes:
      - name: my-route
        paths: [/api]
    # Service-level plugins
    plugins:
      - name: rate-limiting-v2
        config:
          limit: 100
```

### Sync Command

```bash
deck gateway sync ./ascend-astra/kong.yml --kong-addr=http://localhost:8001
```

---

## Security Considerations

### 🔴 Critical: Change Default Passwords

**Before production deployment:**

1. **PostgreSQL Password:**
```yaml
# docker-compose.yml
postgres:
  environment:
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-secure-password-here}
```

2. **Use environment variables:**
```bash
export POSTGRES_PASSWORD="your-secure-password"
docker compose up -d
```

### 🔴 Restrict Admin API Access

**Never expose Admin API (port 8001) to the internet!**

```yaml
# docker-compose.yml
kong:
  ports:
    - "127.0.0.1:8001:8001"  # Bind to localhost only
```

Or use Kong's Admin API authentication.

### 🔴 Enable HTTPS in Production

```yaml
# kong.yml or environment
KONG_PROXY_LISTEN: "0.0.0.0:8000, 0.0.0.0:8443 ssl"
KONG_SSL_CERT: /path/to/cert.pem
KONG_SSL_CERT_KEY: /path/to/key.pem
```

### 🟡 API Key Security

- Store API keys securely
- Use Redis caching to avoid database exposure
- Rotate keys periodically
- Never log full API keys

### 🟡 Rate Limiting

- Enable rate limiting on all public endpoints
- Use appropriate limits per use case
- Consider per-project limits

### 🟡 CORS Configuration

```yaml
# DON'T use in production:
origins: ["*"]
credentials: true  # This combination is invalid

# DO use specific origins:
origins:
  - "https://app.example.com"
  - "https://admin.example.com"
credentials: true
```

---

## Production Deployment

### Recommended Architecture

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │   (HTTPS only)  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
       ┌──────▼──────┐ ┌─────▼─────┐ ┌──────▼──────┐
       │   Kong #1   │ │  Kong #2  │ │   Kong #3   │
       └──────┬──────┘ └─────┬─────┘ └──────┬──────┘
              │              │              │
       ┌──────▼──────────────▼──────────────▼──────┐
       │                Redis Cluster               │
       └───────────────────────────────────────────┘
       ┌───────────────────────────────────────────┐
       │            PostgreSQL (Primary)            │
       │                + Replicas                  │
       └───────────────────────────────────────────┘
```

### Environment-Specific Variables

```bash
# .env.production
POSTGRES_PASSWORD=<strong-password>
KONG_ADMIN_LISTEN=127.0.0.1:8001
KONG_LOG_LEVEL=warn
SEED_DEFAULT_TENANT=false
```

### Health Checks

```bash
# Kong health
curl http://localhost:8001/status

# Database connectivity
curl http://localhost:8001/status | jq '.database.reachable'
```

### Monitoring Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /status` | Kong status |
| `GET /:8001/` | Admin API info |
| `GET /kong-healthcheck` | Health check (excluded from maintenance) |

---

## Unknowns / Needs Confirmation

The following items could not be verified from the repository and may need confirmation:

1. **SSL/TLS Configuration**
   - No SSL certificates are included in the repository
   - Check if SSL termination happens at load balancer level
   - Location: Review production deployment documentation

2. **Redis Cluster Support**
   - Current configuration assumes single Redis instance
   - Check: Does rate-limiting-v2 support Redis Cluster mode?
   - Location: `plugins/rate-limiting-v2/connections.lua`

3. **API Key Hashing**
   - API keys appear to be stored as plain UUIDs in database
   - Check: Is this intentional for lookup performance?
   - Location: `plugins/tenant-manager/utils.lua` - `generate_api_key()`

4. **Database Connection Pooling**
   - Kong uses its default connection pool settings
   - Check: Are custom pool settings needed for high traffic?
   - Location: Review `KONG_PG_*` environment variables

5. **circuit-breaker Plugin Configuration**
   - Plugin is enabled in kong.yml but configuration details are from external package
   - Check: Verify circuit-breaker settings are appropriate
   - Location: `kong.yml` lines 104-117

6. **External Plugin Versions**
   - Three external plugins are installed via LuaRocks
   - Check: Are these versions compatible and up-to-date?
   - Location: `Dockerfile` and `kong.rockspec`

7. **Backup/Recovery Procedures**
   - No backup scripts included
   - Check: What is the backup strategy for production?
   - Location: Ops runbooks (not in repo)

8. **Log Aggregation**
   - Logs go to stdout/stderr
   - Check: Is there a log aggregation system configured?
   - Location: Production infrastructure documentation

