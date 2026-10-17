SELECT 'bronze.customer' AS tbl, count(*) AS rows FROM iceberg.bronze.customer
UNION ALL
SELECT 'bronze.orders', count(*) FROM iceberg.bronze.orders
UNION ALL
SELECT 'bronze.lineitem', count(*) FROM iceberg.bronze.lineitem
UNION ALL
SELECT 'silver.large_orders', count(*) FROM iceberg.silver.large_orders
UNION ALL
SELECT 'silver.q18_joined', count(*) FROM iceberg.silver.q18_joined
UNION ALL
SELECT 'gold.q18', count(*) FROM iceberg.gold.q18_large_volume_customer;
