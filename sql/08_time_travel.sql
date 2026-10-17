-- Time travel: читаем предыдущий снимок Silver после UPDATE volume_flag.
SELECT snapshot_id, committed_at, operation
FROM iceberg.silver."q18_joined$snapshots"
ORDER BY committed_at;

SELECT count(*) AS rows_current
FROM iceberg.silver.q18_joined;

SELECT count(*) AS rows_parent_snapshot
FROM iceberg.silver.q18_joined
FOR VERSION AS OF (
  SELECT parent_id
  FROM iceberg.silver."q18_joined$snapshots"
  WHERE parent_id IS NOT NULL
  ORDER BY committed_at DESC
  LIMIT 1
);
