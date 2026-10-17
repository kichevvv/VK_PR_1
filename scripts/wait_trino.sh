#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "waiting for trino..."
for i in $(seq 1 90); do
  if docker compose exec -T trino trino --execute "SELECT 1" >/dev/null 2>&1; then
    echo "trino is up"
    exit 0
  fi
  sleep 2
done
echo "trino did not become ready" >&2
exit 1
