#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/benchmark"
OUT="$ROOT/benchmark/results.md"

"$ROOT/scripts/wait_trino.sh"

query_ms() {
  local qid="$1"
  docker compose exec -T trino trino --output-format TSV --execute "
    SELECT date_diff('millisecond', started, \"end\")
    FROM system.runtime.queries
    WHERE query_id = '${qid}'
  " | tr -d '\r'
}

run_timed() {
  local label="$1"
  local sql="$2"
  local log
  log=$(mktemp)
  docker compose exec -T trino trino --server localhost:8080 --debug --execute "$sql" >"$log" 2>&1 || {
    cat "$log" >&2
    rm -f "$log"
    return 1
  }
  local qid
  qid=$(grep -E 'Query [0-9a-z_]+ finished' "$log" | tail -1 | awk '{print $2}' || true)
  if [[ -z "${qid}" ]]; then
    qid=$(docker compose exec -T trino trino --output-format TSV --execute "
      SELECT query_id FROM system.runtime.queries
      WHERE state = 'FINISHED'
      ORDER BY created DESC LIMIT 1
    " | tr -d '\r')
  fi
  local ms
  ms=$(query_ms "$qid")
  echo "${label}|${qid}|${ms}" | tee -a "$ROOT/benchmark/results.raw.txt"
  rm -f "$log"
}

bronze_mb() {
  docker compose exec -T trino trino --output-format TSV --execute "
    SELECT round(sum(sz) / 1024.0 / 1024.0, 3) FROM (
      SELECT sum(file_size_in_bytes) AS sz FROM iceberg.bench.\"customer\$files\"
      UNION ALL
      SELECT sum(file_size_in_bytes) FROM iceberg.bench.\"orders\$files\"
      UNION ALL
      SELECT sum(file_size_in_bytes) FROM iceberg.bench.\"lineitem\$files\"
    )
  " | tr -d '\r'
}

: > "$ROOT/benchmark/results.raw.txt"

echo "# Benchmark Bronze codecs (TPC-H sf1, Q18)" >"$OUT"
echo >>"$OUT"
echo "| Сжатие | Запись Bronze, мс | Q18 по Bronze, мс | Размер Bronze, МБ |" >>"$OUT"
echo "|---|---:|---:|---:|" >>"$OUT"

docker compose exec -T trino trino --execute "CREATE SCHEMA IF NOT EXISTS iceberg.bench"

for codec in GZIP ZSTD; do
  echo "===== codec ${codec} ====="
  docker compose exec -T trino trino --execute "DROP TABLE IF EXISTS iceberg.bench.customer"
  docker compose exec -T trino trino --execute "DROP TABLE IF EXISTS iceberg.bench.orders"
  docker compose exec -T trino trino --execute "DROP TABLE IF EXISTS iceberg.bench.lineitem"

  run_timed "write_${codec}_customer" "
    CREATE TABLE iceberg.bench.customer WITH (format='PARQUET', compression_codec='${codec}') AS
    SELECT * FROM tpch.sf1.customer
  "
  run_timed "write_${codec}_orders" "
    CREATE TABLE iceberg.bench.orders WITH (format='PARQUET', compression_codec='${codec}') AS
    SELECT * FROM tpch.sf1.orders
  "
  run_timed "write_${codec}_lineitem" "
    CREATE TABLE iceberg.bench.lineitem WITH (format='PARQUET', compression_codec='${codec}') AS
    SELECT * FROM tpch.sf1.lineitem
  "

  w_c=$(awk -F'|' -v k="write_${codec}_customer" '$1==k{print $3}' "$ROOT/benchmark/results.raw.txt" | tail -1)
  w_o=$(awk -F'|' -v k="write_${codec}_orders" '$1==k{print $3}' "$ROOT/benchmark/results.raw.txt" | tail -1)
  w_l=$(awk -F'|' -v k="write_${codec}_lineitem" '$1==k{print $3}' "$ROOT/benchmark/results.raw.txt" | tail -1)
  write_ms=$((w_c + w_o + w_l))

  run_timed "q18_${codec}" "
    SELECT c.name, c.custkey, o.orderkey, o.orderdate, o.totalprice, sum(l.quantity) AS total_quantity
    FROM iceberg.bench.customer AS c
    JOIN iceberg.bench.orders AS o ON c.custkey = o.custkey
    JOIN iceberg.bench.lineitem AS l ON o.orderkey = l.orderkey
    WHERE o.orderkey IN (
      SELECT orderkey FROM iceberg.bench.lineitem
      GROUP BY orderkey HAVING sum(quantity) > 300
    )
    GROUP BY c.name, c.custkey, o.orderkey, o.orderdate, o.totalprice
    ORDER BY o.totalprice DESC, o.orderdate
    LIMIT 100
  "
  q_ms=$(awk -F'|' -v k="q18_${codec}" '$1==k{print $3}' "$ROOT/benchmark/results.raw.txt" | tail -1)
  mb=$(bronze_mb)

  echo "| ${codec} | ${write_ms} | ${q_ms} | ${mb} |" >>"$OUT"
done

echo >>"$OUT"
echo "Сырые query_id и длительности:" >>"$OUT"
echo '```' >>"$OUT"
cat "$ROOT/benchmark/results.raw.txt" >>"$OUT"
echo '```' >>"$OUT"
cat "$OUT"
