DROP TABLE IF EXISTS iceberg.bronze.orders;

CREATE TABLE iceberg.bronze.orders
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD'
)
AS
SELECT
  orderkey,
  custkey,
  orderstatus,
  totalprice,
  orderdate,
  orderpriority,
  clerk,
  shippriority,
  comment
FROM tpch.sf1.orders;
