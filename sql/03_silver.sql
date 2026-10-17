-- Silver: сначала «крупные» заказы (подзапрос Q18), затем join клиент↔заказ↔позиции.
-- Оставляем только колонки, нужные запросу. Имена клиентов нормализуем trim.

DROP TABLE IF EXISTS iceberg.silver.large_orders;
DROP TABLE IF EXISTS iceberg.silver.q18_joined;

CREATE TABLE iceberg.silver.large_orders
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD'
)
AS
SELECT
  orderkey,
  sum(quantity) AS order_quantity
FROM iceberg.bronze.lineitem
GROUP BY orderkey
HAVING sum(quantity) > 300;

CREATE TABLE iceberg.silver.q18_joined
WITH (
  format = 'PARQUET',
  compression_codec = 'ZSTD',
  partitioning = ARRAY['year(orderdate)']
)
AS
SELECT
  trim(c.name) AS customer_name,
  c.custkey,
  o.orderkey,
  o.orderdate,
  o.totalprice,
  l.quantity,
  lo.order_quantity
FROM iceberg.bronze.customer AS c
JOIN iceberg.bronze.orders AS o
  ON c.custkey = o.custkey
JOIN iceberg.silver.large_orders AS lo
  ON o.orderkey = lo.orderkey
JOIN iceberg.bronze.lineitem AS l
  ON o.orderkey = l.orderkey;
