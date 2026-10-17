#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <sql-file-or-query>" >&2
  exit 1
fi

if [[ -f "$1" ]]; then
  name="$(basename "$1")"
  docker compose exec -T trino trino --server localhost:8080 --catalog iceberg --file "/sql/${name}"
else
  docker compose exec -T trino trino --server localhost:8080 --execute "$1"
fi
