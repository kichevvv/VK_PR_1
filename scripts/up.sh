#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
docker compose up -d --build
"$ROOT/scripts/wait_trino.sh"
docker compose ps
echo
echo "MinIO console:     http://localhost:9001  (minioadmin / minioadmin123)"
echo "Lakekeeper:        http://localhost:8181"
echo "Trino:             http://localhost:8080"
echo "Metabase:          http://localhost:3000"
