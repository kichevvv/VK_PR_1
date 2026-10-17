# Benchmark Bronze codecs (TPC-H sf1, Q18)

| Сжатие | Запись Bronze, мс | Q18 по Bronze, мс | Размер Bronze, МБ |
|---|---:|---:|---:|
| GZIP | 51525 | 7909 | 182.557000000000 |
| ZSTD | 169701 | 16642 | 187.729000000000 |

Сырые query_id и длительности:
```
write_GZIP_customer|20261017_154224_00034_ksjjh|4009
write_GZIP_orders|20261017_154232_00037_ksjjh|10651
write_GZIP_lineitem|20261017_154246_00040_ksjjh|36865
q18_GZIP|20261017_154331_00043_ksjjh|7909
write_ZSTD_customer|20261017_154350_00050_ksjjh|3844
write_ZSTD_orders|20261017_154402_00053_ksjjh|12004
write_ZSTD_lineitem|20261017_154421_00056_ksjjh|153853
q18_ZSTD|20261017_154708_00059_ksjjh|16642
```
