#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/wait_trino.sh"

run() {
  local f="$1"
  local name
  name="$(basename "$f")"
  echo "=== $f ==="
  docker compose exec -T trino trino --server localhost:8080 --file "/sql/${name}"
}

run "$ROOT/sql/01_schemas.sql"
run "$ROOT/sql/02a_bronze_customer.sql"
run "$ROOT/sql/02b_bronze_orders.sql"
run "$ROOT/sql/02c_bronze_lineitem.sql"
run "$ROOT/sql/03_silver.sql"
run "$ROOT/sql/04_gold.sql"

echo "=== row counts ==="
mkdir -p "$ROOT/benchmark"
run "$ROOT/sql/09_stats.sql" | tee "$ROOT/benchmark/row_counts.txt"

echo "=== file sizes, MB ==="
run "$ROOT/sql/10_file_sizes.sql" | tee "$ROOT/benchmark/file_sizes.txt"

echo "=== gold Q18 ==="
run "$ROOT/sql/05_q18.sql"

echo "=== schema evolution on silver ==="
docker compose exec -T trino trino --server localhost:8080 --execute "
ALTER TABLE iceberg.silver.q18_joined ADD COLUMN volume_flag VARCHAR
" || echo "ADD COLUMN skipped (already exists?)"
docker compose exec -T trino trino --server localhost:8080 --execute "
UPDATE iceberg.silver.q18_joined SET volume_flag = 'LARGE_QTY_GT_300'
"

echo "=== snapshots after evolution ==="
docker compose exec -T trino trino --server localhost:8080 --execute "
SELECT snapshot_id, committed_at, operation, parent_id
FROM iceberg.silver.\"q18_joined\$snapshots\"
ORDER BY committed_at
"

PARENT=$(docker compose exec -T trino trino --server localhost:8080 --output-format TSV --execute "
SELECT parent_id
FROM iceberg.silver.\"q18_joined\$snapshots\"
WHERE parent_id IS NOT NULL
ORDER BY committed_at DESC
LIMIT 1
" | tr -d '\r')

echo "restore-from-snapshot example (read-only time travel), parent=$PARENT"
docker compose exec -T trino trino --server localhost:8080 --execute "
SELECT count(*) AS rows_at_parent
FROM iceberg.silver.q18_joined FOR VERSION AS OF ${PARENT}
"

echo "pipeline done"
