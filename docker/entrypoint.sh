#!/bin/bash
set -euo pipefail
set -x

run_seed_in_background() {
    if [ "${SEED_DEFAULT_TENANT:-false}" = "true" ]; then
        echo "[entrypoint] Will seed default tenant after Kong starts..."
        (
            until curl -sf http://127.0.0.1:8001/status >/dev/null; do
                sleep 2
            done
            /usr/local/bin/seed-tenant.sh || \
              echo "[entrypoint] WARNING: seed-tenant failed"
        ) &
    fi
}

run_seed_in_background

exec /docker-entrypoint.sh kong docker-start
