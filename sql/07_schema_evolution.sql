-- Schema evolution на Silver: добавляем колонку-маркер сегмента.
ALTER TABLE iceberg.silver.q18_joined ADD COLUMN IF NOT EXISTS volume_flag VARCHAR;

UPDATE iceberg.silver.q18_joined
SET volume_flag = 'LARGE_QTY_GT_300';

COMMENT ON TABLE iceberg.silver.q18_joined IS
  'Q18 silver: крупные заказы, join customer/orders/lineitem';
