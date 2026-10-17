-- Bronze: сырые TPC-H таблицы без бизнес-фильтрации.
-- Колонки оставляем все: это слой посадки, а не витрина.
-- Партиций нет: сырой dump не режем под конкретный запрос.

DROP TABLE IF EXISTS iceberg.bronze.customer;
DROP TABLE IF EXISTS iceberg.bronze.orders;
DROP TABLE IF EXISTS iceberg.bronze.lineitem;

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

CREATE TABLE iceberg.bronze.lineitem
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD'
)
AS
SELECT
  orderkey,
  partkey,
  suppkey,
  linenumber,
  quantity,
  extendedprice,
  discount,
  tax,
  returnflag,
  linestatus,
  shipdate,
  commitdate,
  receiptdate,
  shipinstruct,
  shipmode,
  comment
FROM tpch.sf1.lineitem;
