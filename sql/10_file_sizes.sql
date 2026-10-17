SELECT 'bronze.customer' AS tbl, count(*) AS files, round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3) AS mb
FROM iceberg.bronze."customer$files"
UNION ALL
SELECT 'bronze.orders', count(*), round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3)
FROM iceberg.bronze."orders$files"
UNION ALL
SELECT 'bronze.lineitem', count(*), round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3)
FROM iceberg.bronze."lineitem$files"
UNION ALL
SELECT 'silver.large_orders', count(*), round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3)
FROM iceberg.silver."large_orders$files"
UNION ALL
SELECT 'silver.q18_joined', count(*), round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3)
FROM iceberg.silver."q18_joined$files"
UNION ALL
SELECT 'gold.q18', count(*), round(sum(file_size_in_bytes) / 1024.0 / 1024.0, 3)
FROM iceberg.gold."q18_large_volume_customer$files";
