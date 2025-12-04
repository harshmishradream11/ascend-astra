# Ascend Kong

A Kong Gateway setup with custom plugins for API management and traffic control.

## Plugins

| Plugin | Description | Priority |
|--------|-------------|----------|
| [maintenance](plugins/maintenance/) | Block traffic with maintenance responses | 11000 |
| [conditional-req-termination](plugins/conditional-req-termination/) | Terminate requests based on query conditions | 8001 |
| [strip-headers](plugins/strip-headers/) | Remove headers by prefix | 8000 |
| [swap-header](plugins/swap-header/) | Rename/swap request headers | 1000 |
| [rate-limiting-v2](plugins/rate-limiting-v2/) | Advanced rate limiting with Redis | 960 |

## Quick Start

### Prerequisites

- Docker and Docker Compose

### Start Services

```bash
./scripts/docker-start.sh
```

### Stop Services

```bash
./scripts/docker-stop.sh

# Remove all data:
docker compose down -v
```

## Services

| Service        | URL                   | Description         |
|----------------|----------------------|---------------------|
| Kong Proxy     | http://localhost:8000 | Main API gateway    |
| Kong Admin API | http://localhost:8001 | Kong administration |
| Kong Manager   | http://localhost:8002 | Kong GUI dashboard  |
| PostgreSQL     | localhost:5432        | Database            |
| Redis          | localhost:6379        | Rate limiting cache |

## Project Structure

```
ascend-kong/
├── Dockerfile
├── docker-compose.yml
├── plugins/
│   ├── conditional-req-termination/
│   ├── maintenance/
│   ├── rate-limiting-v2/
│   ├── strip-headers/
│   └── swap-header/
├── ascend-kong/
│   ├── kong.rockspec
│   └── kong.yml
└── scripts/
    ├── docker-start.sh
    ├── docker-stop.sh
    ├── deck-dump.sh
    ├── deck-sync.sh
    └── setup.sh
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

## License

MIT
