DROP TABLE IF EXISTS iceberg.bronze.customer;

CREATE TABLE iceberg.bronze.customer
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD'
)
AS
SELECT
  custkey,
  name,
  address,
  nationkey,
  phone,
  acctbal,
  mktsegment,
  comment
FROM tpch.sf1.customer;
