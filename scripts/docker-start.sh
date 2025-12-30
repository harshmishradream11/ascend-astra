#!/bin/bash

# ============================================
# Ascend Astra Docker Startup Script
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "============================================"
echo "  Ascend Astra - Docker Startup"
echo "============================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Stop any existing containers
echo ""
echo "Stopping any existing containers..."
docker compose down --remove-orphans 2>/dev/null || true

# Build and start services
echo ""
echo "Building and starting services..."
docker compose up --build -d

# Wait for Kong to be ready
echo ""
echo "Waiting for Kong to be ready..."
max_retries=30
retry=0
while [ $retry -lt $max_retries ]; do
    if curl -s http://localhost:8001/status > /dev/null 2>&1; then
        echo "Kong is ready!"
        break
    fi
    retry=$((retry + 1))
    echo "Waiting for Kong... ($retry/$max_retries)"
    sleep 3
done

if [ $retry -eq $max_retries ]; then
    echo "Warning: Kong may not be fully ready yet"
fi

# Sync Kong configuration using deck
echo ""
echo "Syncing Kong configuration..."
if command -v deck &> /dev/null; then
    "$SCRIPT_DIR/deck-sync.sh"
else
    echo "Warning: deck CLI not found. Skipping configuration sync."
    echo "Install deck from: https://docs.konghq.com/deck/latest/installation/"
fi

# Display status
echo ""
echo "============================================"
echo "  Ascend Astra is running!"
echo "============================================"
echo ""
echo "Services:"
echo "  - Kong Proxy:     http://localhost:8000"
echo "  - Kong Admin API: http://localhost:8001"
echo "  - Kong Manager:   http://localhost:8002"
echo "  - PostgreSQL:     localhost:5432"
echo "  - Redis:          localhost:6379"
echo ""
echo "Tenant Manager API Endpoints:"
echo "  - POST   /v1/tenants                              - Create tenant"
echo "  - GET    /v1/tenants                              - List tenants"
echo "  - GET    /v1/tenants/{tenant_id}                  - Get tenant"
echo "  - POST   /v1/tenants/{id}/projects                - Create project"
echo "  - GET    /v1/tenants/{id}/projects                - List projects"
echo "  - POST   /v1/tenants/{id}/projects/{id}/api-keys  - Generate API key"
echo ""
echo "View logs:  docker compose logs -f kong"
echo "Stop:       docker compose down"
echo ""

# Wait for seeding to complete and show default tenant
sleep 5
echo "Checking default tenant..."
curl -s http://localhost:8000/v1/tenants 2>/dev/null | jq . 2>/dev/null || echo "(Install jq for prettier output)"

