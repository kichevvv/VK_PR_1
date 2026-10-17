SELECT
  name,
  custkey,
  orderkey,
  orderdate,
  totalprice,
  total_quantity
FROM iceberg.gold.q18_large_volume_customer
ORDER BY totalprice DESC, orderdate
LIMIT 100;
