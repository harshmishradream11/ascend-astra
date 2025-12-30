# Ascend Astra

A comprehensive Kong Gateway setup with custom plugins for multi-tenant API management, authentication, traffic control, and rate limiting.

## Overview

Ascend Astra is a Kong Gateway distribution that packages:

- **8 Custom Plugins** for API key authentication, tenant management, CORS, rate limiting, and traffic control
- **3 Open-Source Plugins** (circuit-breaker, host-interpolate-by-header, advanced-router)
- **Complete Docker Infrastructure** with PostgreSQL and Redis
- **Declarative Configuration** via Kong deck

## Compatibility

| Component | Version |
|-----------|---------|
| Kong Gateway | 3.7.1 (OSS) |
| PostgreSQL | 16 (Alpine) |
| Redis | 7 (Alpine) |
| Deck CLI | 1.40.2 |
| LuaRocks | 3.12.0 |
| Database Mode | PostgreSQL (DB mode) |

## Custom Plugins

| Plugin | Priority | Description |
|--------|----------|-------------|
| [maintenance](#maintenance) | 11000 | Block traffic with maintenance responses |
| [conditional-req-termination](#conditional-req-termination) | 8001 | Terminate requests based on query conditions |
| [strip-headers](#strip-headers) | 8000 | Remove headers by prefix |
| [cors](#cors) | 2000 | Handle CORS with wildcard subdomain support |
| [api-key-auth](#api-key-auth) | 1100 | Validate API keys with Redis caching |
| [swap-header](#swap-header) | 1000 | Rename/swap request headers |
| [rate-limiting-v2](#rate-limiting-v2) | 960 | Advanced rate limiting with Redis |
| [tenant-manager](#tenant-manager) | 900 | Multi-tenant management API |

## Quickstart

### Prerequisites

- Docker and Docker Compose
- (Optional) [deck CLI](https://docs.konghq.com/deck/latest/installation/) for configuration management

### Start Services

```bash
# Clone the repository
git clone <repository-url>
cd ascend-astra

# Start all services
./scripts/docker-start.sh
```

This will:
1. Start PostgreSQL, Redis, and Kong Gateway
2. Run Kong migrations
3. Sync the declarative configuration from `kong.yml`
4. Seed a default tenant and project

### Verify Installation

```bash
# Check Kong status
curl http://localhost:8001/status

# List enabled plugins
curl http://localhost:8001/plugins

# List tenants (via tenant-manager plugin)
curl http://localhost:8000/v1/tenants
```

### Stop Services

```bash
./scripts/docker-stop.sh

# Remove all data:
docker compose down -v
```

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Kong Proxy | http://localhost:8000 | Main API gateway |
| Kong Admin API | http://localhost:8001 | Kong administration |
| Kong Manager | http://localhost:8002 | Kong GUI dashboard |
| PostgreSQL | localhost:8032 | Database |
| Redis | localhost:8079 | Rate limiting cache |

## Project Structure

```
ascend-astra/
├── Dockerfile                    # Custom Kong image
├── docker-compose.yml            # Infrastructure setup
├── docker/
│   ├── entrypoint.sh             # Custom entrypoint
│   ├── init-db.sql               # Database initialization
│   └── seed-tenant.sh            # Default tenant seeding
├── plugins/
│   ├── api-key-auth/             # API key authentication
│   ├── conditional-req-termination/
│   ├── cors/                     # CORS handling
│   ├── maintenance/              # Maintenance mode
│   ├── rate-limiting-v2/         # Advanced rate limiting
│   ├── strip-headers/            # Header stripping
│   ├── swap-header/              # Header swapping
│   └── tenant-manager/           # Multi-tenant management
├── ascend-astra/
│   ├── kong.rockspec             # LuaRocks specification
│   └── kong.yml                  # Declarative Kong config
└── scripts/
    ├── docker-start.sh           # Start services
    ├── docker-stop.sh            # Stop services
    ├── deck-dump.sh              # Export Kong config
    ├── deck-sync.sh              # Import Kong config
    └── setup.sh                  # Initial setup
```

## Development

### View Logs

```bash
docker compose logs -f kong
```

### Rebuild After Plugin Changes

```bash
docker compose build kong
docker compose up -d kong
```

### Export Current Configuration

```bash
./scripts/deck-dump.sh
```

### Sync Configuration Changes

```bash
./scripts/deck-sync.sh
```

## Documentation

- [Plugin Reference](docs/PLUGINS.md) - Complete plugin configuration reference
- [Installation Guide](docs/INSTALLATION.md) - Detailed installation steps
- [Usage Guide](docs/USAGE.md) - Common workflows and examples
- [Configuration Reference](docs/CONFIGURATION.md) - Environment variables and config files

## License

MIT

