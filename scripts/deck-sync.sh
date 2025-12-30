#!/usr/bin/env bash
set -euo pipefail

# Sync Kong configuration from kong.yaml
# Usage: ./deck-sync.sh [KONG_ADMIN_URL] [CONFIG_FILE]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

KONG_ADMIN_URL=${1:-"http://localhost:8001"}
CONFIG_FILE=${2:-"$PROJECT_ROOT/ascend-astra/kong.yml"}

echo "Syncing Kong config to: $KONG_ADMIN_URL"
echo "Using config file: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

export DECK_ANALYTICS=off
deck gateway sync "$CONFIG_FILE" --kong-addr="$KONG_ADMIN_URL"

echo "✓ Kong configuration synced successfully"