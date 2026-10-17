DROP TABLE IF EXISTS iceberg.bronze.lineitem;

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
