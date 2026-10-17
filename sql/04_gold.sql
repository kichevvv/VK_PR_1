-- Gold: витрина Q18 — топ-100 крупных заказов по сумме.

DROP TABLE IF EXISTS iceberg.gold.q18_large_volume_customer;

CREATE TABLE iceberg.gold.q18_large_volume_customer
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD'
)
AS
SELECT
  customer_name AS name,
  custkey,
  orderkey,
  orderdate,
  totalprice,
  sum(quantity) AS total_quantity
FROM iceberg.silver.q18_joined
GROUP BY customer_name, custkey, orderkey, orderdate, totalprice
ORDER BY totalprice DESC, orderdate
LIMIT 100;
