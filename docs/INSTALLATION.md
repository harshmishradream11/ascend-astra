# Installation Guide

Complete installation and setup instructions for Ascend Astra Kong Gateway.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Installation (Docker)](#quick-installation-docker)
3. [Manual Installation](#manual-installation)
4. [Verify Installation](#verify-installation)
5. [Plugin Installation](#plugin-installation)
6. [Database Setup](#database-setup)
7. [Configuration Sync](#configuration-sync)
8. [Upgrade Guide](#upgrade-guide)

---

## Prerequisites

### Required

- **Docker** >= 20.10
- **Docker Compose** >= 2.0

### Optional

- **deck CLI** >= 1.40.0 - For configuration management
- **jq** - For JSON formatting in terminal
- **curl** - For API testing

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 1 core | 2+ cores |
| Memory | 2 GB | 4+ GB |
| Disk | 5 GB | 10+ GB |

---

## Quick Installation (Docker)

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd ascend-astra
```

### Step 2: Start Services

```bash
./scripts/docker-start.sh
```

This single command will:
1. Stop any existing containers
2. Build the custom Kong image with all plugins
3. Start PostgreSQL, Redis, and Kong
4. Run database migrations
5. Sync declarative configuration
6. Seed default tenant (optional)

### Step 3: Verify

```bash
# Check Kong is running
curl http://localhost:8001/status

# List tenants
curl http://localhost:8000/v1/tenants
```

### Expected Output

```
============================================
  Ascend Astra is running!
============================================

Services:
  - Kong Proxy:     http://localhost:8000
  - Kong Admin API: http://localhost:8001
  - Kong Manager:   http://localhost:8002
  - PostgreSQL:     localhost:8032
  - Redis:          localhost:8079
```

---

## Manual Installation

### Step 1: Build Docker Image

```bash
docker compose build kong
```

This builds a custom Kong image with:
- Kong Gateway 3.7.1
- deck CLI 1.40.2
- All custom plugins
- LuaRocks dependencies

### Step 2: Start Infrastructure

```bash
# Start PostgreSQL and Redis first
docker compose up -d postgres redis

# Wait for them to be healthy
docker compose ps
```

### Step 3: Run Migrations

```bash
docker compose up kong-migrations
```

This runs:
- Kong core migrations
- Plugin migrations (tenant-manager tables)

### Step 4: Start Kong

```bash
docker compose up -d kong
```

### Step 5: Sync Configuration

```bash
# Wait for Kong to be healthy
sleep 10

# Sync declarative config
docker compose up deck-sync

# Or manually:
./scripts/deck-sync.sh http://localhost:8001 ./ascend-astra/kong.yml
```

---

## Verify Installation

### Check Kong Status

```bash
curl -s http://localhost:8001/status | jq
```

Expected response:
```json
{
  "server": {
    "connections_active": 1,
    "connections_accepted": 1,
    "connections_handled": 1,
    "connections_reading": 0,
    "connections_writing": 1,
    "connections_waiting": 0,
    "total_requests": 1
  },
  "database": {
    "reachable": true
  }
}
```

### List Enabled Plugins

```bash
curl -s http://localhost:8001/plugins | jq '.data[] | {name: .name, enabled: .enabled}'
```

### Verify Custom Plugins Available

```bash
curl -s http://localhost:8001/ | jq '.plugins.available_on_server' | grep -E "maintenance|cors|api-key-auth|tenant-manager|rate-limiting-v2"
```

### Check Services

```bash
curl -s http://localhost:8001/services | jq '.data[] | {name: .name, host: .host, port: .port}'
```

### Check Routes

```bash
curl -s http://localhost:8001/routes | jq '.data[] | {name: .name, paths: .paths}'
```

### Test Tenant Manager API

```bash
# List tenants
curl -s http://localhost:8000/v1/tenants | jq

# Should return default tenant if seeding was enabled
```

---

## Plugin Installation

### Verify Plugins Are Loaded

All custom plugins should appear in Kong's available plugins:

```bash
curl -s http://localhost:8001/ | jq '.plugins.available_on_server | keys | .[]' | grep -E "^\"(maintenance|cors|api-key-auth|tenant-manager|rate-limiting-v2|strip-headers|swap-header|conditional-req-termination)\""
```

### Plugin Installation Path

Plugins are installed to:
```
/usr/local/share/lua/5.1/kong/plugins/<plugin-name>/
```

Each plugin directory contains:
- `handler.lua` - Plugin logic
- `schema.lua` - Configuration schema

### Verify Plugin Files (Inside Container)

```bash
docker compose exec kong ls -la /usr/local/share/lua/5.1/kong/plugins/
```

### Check KONG_PLUGINS Environment

```bash
docker compose exec kong printenv KONG_PLUGINS
```

Expected output:
```
bundled,cors,maintenance,conditional-req-termination,strip-headers,rate-limiting-v2,api-key-auth,tenant-manager,circuit-breaker,host-interpolate-by-header,advanced-router,swap-header
```

---

## Database Setup

### Tables Created by Migrations

The tenant-manager plugin creates these tables:

```sql
-- Tenants table
CREATE TABLE tenants (
    id              UUID PRIMARY KEY,
    name            VARCHAR(255) NOT NULL UNIQUE,
    description     TEXT,
    contact_email   VARCHAR(255) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP WITH TIME ZONE,
    updated_at      TIMESTAMP WITH TIME ZONE
);

-- Projects table
CREATE TABLE projects (
    id              UUID PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    project_key     VARCHAR(100) NOT NULL,
    name            VARCHAR(255) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP WITH TIME ZONE,
    updated_at      TIMESTAMP WITH TIME ZONE,
    UNIQUE(tenant_id, project_key)
);

-- API Keys table
CREATE TABLE api_keys (
    id              UUID PRIMARY KEY,
    project_id      UUID NOT NULL REFERENCES projects(id),
    name            VARCHAR(255) NOT NULL,
    api_key         UUID NOT NULL UNIQUE,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP WITH TIME ZONE,
    updated_at      TIMESTAMP WITH TIME ZONE,
    last_rotated_at TIMESTAMP WITH TIME ZONE,
    last_used_at    TIMESTAMP WITH TIME ZONE
);
```

### Verify Tables Exist

```bash
docker compose exec postgres psql -U kong -d kong -c "\dt"
```

Expected tables include:
- `tenants`
- `projects`
- `api_keys`
- Kong's internal tables

### Connect to Database

```bash
# Via Docker
docker compose exec postgres psql -U kong -d kong

# Via external client
psql -h localhost -p 8032 -U kong -d kong
# Password: kongpass
```

---

## Configuration Sync

### Using deck CLI

deck is the recommended way to manage Kong configuration.

#### Export Current Configuration

```bash
./scripts/deck-dump.sh
# Or:
deck gateway dump --kong-addr=http://localhost:8001 --output-file=kong.yml
```

#### Import Configuration

```bash
./scripts/deck-sync.sh
# Or:
deck gateway sync ./ascend-astra/kong.yml --kong-addr=http://localhost:8001
```

#### Validate Configuration

```bash
deck gateway validate ./ascend-astra/kong.yml --kong-addr=http://localhost:8001
```

#### Diff Configuration

```bash
deck gateway diff ./ascend-astra/kong.yml --kong-addr=http://localhost:8001
```

### Configuration File Format

`kong.yml` uses deck's declarative format (v3.0):

```yaml
_format_version: "3.0"

services:
  - name: my-service
    url: http://upstream:8080
    routes:
      - name: my-route
        paths:
          - /api

plugins:
  - name: cors
    enabled: true
    config:
      origins:
        - "*"
```

---

## Upgrade Guide

### Upgrading Kong Version

1. Update `Dockerfile`:
```dockerfile
FROM kong:3.8.0-ubuntu  # New version
```

2. Rebuild and restart:
```bash
docker compose down
docker compose build kong
docker compose up -d
```

3. Run migrations:
```bash
docker compose exec kong kong migrations up
docker compose exec kong kong migrations finish
```

### Upgrading Plugins

1. Update plugin files in `plugins/` directory

2. Rebuild Kong image:
```bash
docker compose build kong
```

3. Restart Kong:
```bash
docker compose up -d kong
```

### Backup Before Upgrade

```bash
# Backup database
docker compose exec postgres pg_dump -U kong kong > backup.sql

# Backup configuration
./scripts/deck-dump.sh http://localhost:8001 ./backup/
```

### Rollback Procedure

```bash
# Restore database
docker compose exec -T postgres psql -U kong kong < backup.sql

# Sync previous configuration
deck gateway sync ./backup/kong.yaml --kong-addr=http://localhost:8001
```

---

## Next Steps

- [Plugin Reference](./PLUGINS.md) - Configure plugins
- [Usage Guide](./USAGE.md) - Common workflows
- [Configuration Reference](./CONFIGURATION.md) - Environment variables

