#!/bin/bash

# ============================================
# Ascend Kong Docker Stop Script
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Stopping Ascend Kong containers..."
docker compose down

echo ""
echo "Containers stopped."
echo "To remove volumes as well, run: docker compose down -v"

