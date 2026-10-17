# Отчёт по практической №1

Репозиторий с кодом, compose-файлом и SQL пайплайна.

## 1. Вариант и масштаб

| Поле | Значение |
|---|---|
| ФИО (как в VK Education) | Иванищев Кирилл Александрович |
| Вариант (запрос) | Q18 «Large Volume Customer» |
| Масштаб sfN | **sf1** |
| Почему выбрал такой масштаб | В формулировке варианта стоит `tpch.sf1`. На sf1 `lineitem` — ~6.0 млн строк, `orders` — 1.5 млн, `customer` — 150 тыс.: этого достаточно, чтобы сжатие GZIP/ZSTD и join Q18 были заметны по времени и по размеру Parquet, и при этом стек поднимается на ноутбуке без генерации sf10 (~10× больше). sf0.01 слишком мелкий: разница кодеков утонула бы в шуме. |

## 2. Поднятые сервисы — и почему именно они

| Сервис | Роль в стеке | Почему именно он (а не альтернатива) |
|---|---|---|
| MinIO / Silo | S3-совместимое объектное хранилище: сюда Iceberg кладёт parquet data/metadata | Нужен S3 API и консоль без AWS. Официальные `minio/minio` и `quay.io/minio/minio` с осени 2026 не отдаются анонимно. Silo (`pgsty/silo`) — публичный drop-in с тем же S3 и `MINIO_*`; роль в стеке та же, что у MinIO в задании. HDFS тяжелее; локальный диск без S3 не показывает lakehouse. |
| PostgreSQL | БД метаданных Lakekeeper (склады, namespaces, табличные указатели) | Lakekeeper хранит каталог не в файлах MinIO, а в Postgres; SQLite хуже при нескольких контейнерах, облачный RDS для лабораторной работы избыточен. |
| Lakekeeper | Iceberg REST Catalog | Открытый REST-каталог, который Trino понимает штатным `iceberg.catalog.type=rest`. Hive Metastore тянет ещё один Thrift-стек; JDBC-каталог Iceberg беднее по warehouse/credentials. |
| Trino | SQL-движок: читает каталог в Lakekeeper, данные в MinIO; умеет TPC-H connector (генерация sf1 без скачивания дампов) | Один движок и для посадки Bronze (`CREATE TABLE AS SELECT` из `tpch.sf1`), и для Silver/Gold, и для бенчмарка. Spark мощнее для ETL, но дольше стартует и тяжелее по RAM. |
| Metabase | BI поверх Gold (и проверка Bronze) | Легче Superset по compose: один контейнер + Starburst-драйвер. Нужен именно UI, а не ещё один SQL-CLI. |

Проверка: `docker compose ps` / `docker ps` — контейнеры `lakehouse-minio`, `lakehouse-pg`, `lakehouse-lakekeeper`, `lakehouse-trino`, `lakehouse-metabase`.

### Скрипты, которыми поднимал стек

```bash
# Стек lakehouse: Silo/MinIO, Postgres, миграции Lakekeeper, warehouse, Trino.
docker compose up -d

# Metabase (профиль bi — отдельно, чтобы ETL не делил RAM с BI).
docker compose --profile bi up -d

# Дождаться SQL-эндпоинта Trino.
./scripts/wait_trino.sh

# Медальон Q18 + schema evolution + чтение снапшота.
./scripts/pipeline.sh

# Бенчмарк кодеков на Bronze (GZIP vs ZSTD) и время Q18.
./scripts/benchmark.sh
```

Ключевые куски compose (полный файл — `docker-compose.yml`):

```yaml
# S3 (сервис minio): образ pgsty/silo — MinIO-совместимый S3, порты 9000/9001
# PostgreSQL — метаданные Lakekeeper (сервис db)
# migrate + lakekeeper — Iceberg REST Catalog :8181
# lakekeeper-bootstrap — POST /management/v1/bootstrap и создание warehouse demo
# trino — SQL-движок :8080, каталоги trino/catalog/{iceberg,tpch}.properties
# metabase — BI :3000, драйвер Starburst качается сервисом metabase-plugin
```

Warehouse в Lakekeeper (`lakekeeper/create-warehouse.json`): бакет `warehouse`, prefix `lakehouse`, `flavor: s3-compat`, STS выключен — Trino ходит в MinIO со своими ключами. Это проще, чем поднимать STS MinIO, и достаточно для лабораторной работы.

## 3. Разбор запроса — какие данные нужны

Q18: заказы, у которых `sum(lineitem.quantity) > 300`, затем join с клиентом и позициями, `GROUP BY` заказа, `ORDER BY totalprice DESC`, `LIMIT 100`.

| Таблица TPC-H | Нужные колонки | Что запрос с ними делает |
|---|---|---|
| customer | `custkey`, `name` | Джойн с orders по `custkey`; `name` в SELECT |
| orders | `orderkey`, `custkey`, `orderdate`, `totalprice` | Джойн с customer и lineitem; фильтр через IN (крупные orderkey); `totalprice`/`orderdate` — сортировка и вывод |
| lineitem | `orderkey`, `quantity` | Подзапрос: `GROUP BY orderkey HAVING sum(quantity) > 300`; во внешнем запросе `sum(quantity)` как `total_quantity` |

Остальные колонки TPC-H (адрес, комментарии, shipdate, …) в Q18 не участвуют. На **Bronze** их всё равно оставляю: слой сырой. На **Silver/Gold** обрезаю до нужных.

## 4. Медальон — решения по каждому слою

Строки TPC-H sf1 фиксированы спецификацией. Размеры файлов — после `./scripts/pipeline.sh` из `$files` (см. `sql/10_file_sizes.sql`) и из MinIO Console → бакет `warehouse`.

Как мерить:

```sql
SELECT count(*) FROM iceberg.bronze.lineitem;
SELECT round(sum(file_size_in_bytes)/1024.0/1024.0, 3) AS mb
FROM iceberg.bronze."lineitem$files";
```

### Bronze (сырой)

| Таблица | Колонки (что оставил) | Строк | Вес, МБ | Формат | Сжатие | Партиционирование | Обоснование |
|---|---|---:|---:|---|---|---|---|
| bronze.customer | все 8 колонок TPC-H | 150000 | 7.825 | PARQUET | ZSTD | нет | Сырой слой = посадка as-is. Parquet колоночный, ZSTD — штатный кодек Iceberg/Trino. Партиции на 150k строк не окупаются. |
| bronze.orders | все 9 колонок | 1500000 | 34.978 | PARQUET | ZSTD | нет | Не режу по дате на Bronze: сырой dump должен воспроизводиться целиком. |
| bronze.lineitem | все 16 колонок | 6001215 | 144.901 | PARQUET | ZSTD | нет | Самая тяжёлая таблица (2 parquet-файла). Партиция на Bronze связала бы сырой слой с одним сценарием (Q18 не фильтрует по shipdate). |

### Silver (очищенный)

| Таблица | Колонки (что оставил) | Строк | Вес, МБ | Формат | Сжатие | Партиционирование | Обоснование |
|---|---|---:|---:|---|---|---|---|
| silver.large_orders | `orderkey`, `order_quantity` | 57 (заказы с qty>300) | 0.001 | PARQUET | ZSTD | нет | Материализация подзапроса Q18. На sf1 крупных заказов всего 57 — узкая таблица ключей, партиция не нужна. |
| silver.q18_joined | `customer_name` (trim), `custkey`, `orderkey`, `orderdate`, `totalprice`, `quantity`, `order_quantity` | 399 | 0.013 | PARQUET | ZSTD | `year(orderdate)` | Сначала фильтр крупных заказов, потом join — меньше shuffle, чем join всех 6 млн позиций. 399 строк = позиции этих 57 заказов. Партиция по году: срез без переписывания Gold. |

### Gold (витрина)

| Таблица | Колонки | Строк | Вес, МБ | Формат | Сжатие | Партиционирование | Обоснование |
|---|---|---:|---:|---|---|---|---|
| gold.q18_large_volume_customer | `name`, `custkey`, `orderkey`, `orderdate`, `totalprice`, `total_quantity` | 57 | 0.002 | PARQUET | ZSTD | нет | Готовый ответ Q18 для BI. `LIMIT 100`, но на sf1 qualifying-заказов 57 — столько и в витрине. Партиционировать бессмысленно. |

## 5. Тесты производительности

Прогон: `./scripts/benchmark.sh`. Bronze в схеме `iceberg.bench` пересоздаётся с `compression_codec = GZIP` и `ZSTD`. Запись — сумма CTAS customer+orders+lineitem. Запрос — полный Q18 по Bronze. Размер — сумма `$files`. Время — `system.runtime.queries` (миллисекунды).

| Сжатие на Bronze | Запись, мс | Время Q18 | Размер Bronze, МБ | Вывод |
|---|---:|---:|---:|---|
| GZIP | 51525 | **7909 мс** (~7.9 с) | **182.557** | На этом прогоне лучше по всем трём метрикам. |
| ZSTD | 169701 | 16642 мс (~16.6 с) | 187.729 | Запись `lineitem` 153.9 с против 36.9 с у GZIP — похоже на просадку JVM/диска на втором прогоне, не «честный» проигрыш кодека. Размер на ~3% больше GZIP. |

Сырой лог query_id: `benchmark/results.raw.txt`, сводка — `benchmark/results.md`.

Дополнительно сравнение записи (не только SELECT) заложено в тот же скрипт: колонка «Запись Bronze, мс».

## 6. Часть 2 — осмысление и работа с инструментами

### 6.1. Понять и объяснить

| Вопрос | Твой ответ |
|---|---|
| Зачем нужны большие данные и lakehouse (а не обычная БД/хранилище)? | Операционная БД плохо держит сырые многолетние факты, полуструктурированные выгрузки и независимые движки над одними файлами. «Просто S3» без каталога не даёт транзакций, схемы и time travel. Lakehouse (объектное хранилище + табличный формат Iceberg + REST-каталог + SQL-движок) разделяет compute и storage: Bronze можно дописывать, Silver/Gold пересобирать другим движком, BI читает те же parquet, не копируя всё в Postgres. |
| Пример schema evolution на Silver: добавил/переименовал колонку — что произошло? | `ALTER TABLE iceberg.silver.q18_joined ADD COLUMN volume_flag VARCHAR;` затем `UPDATE … SET volume_flag = 'LARGE_QTY_GT_300'`. Iceberg пишет новый metadata.json и новые data-файлы (для UPDATE), старые снапшоты остаются. Чтение старого снапшота колонки не знает; текущий — знает. Переименование (`ALTER TABLE … RENAME COLUMN`) меняет только метаданные, без переписывания всех parquet. |
| Пример скрипта восстановления данных из снапшота (time travel) | См. ниже. |

```sql
-- список точек восстановления
SELECT snapshot_id, parent_id, committed_at, operation
FROM iceberg.silver."q18_joined$snapshots"
ORDER BY committed_at;

-- прочитать состояние до UPDATE (parent_id последнего снапшота)
SELECT *
FROM iceberg.silver.q18_joined
FOR VERSION AS OF 4873582094410174599;

-- фактически откатить текущую таблицу
CALL iceberg.system.rollback_to_snapshot('silver', 'q18_joined', 4873582094410174599);
```

После пайплайна: append `4873582094410174599`, overwrite (UPDATE `volume_flag`) `6260265994635141658`. Time travel читает parent — состояние до UPDATE, без колонки в данных.

### 6.2. Подключить инструмент к lakehouse

| Инструмент | Почему выбрал именно его |
|---|---|
| Metabase (+ Starburst driver 6.1.0) | Нужен BI, не второй движок: Gold — 57 строк для дашборда «крупные заказчики». Metabase в одном контейнере, есть JDBC к Trino. Superset тяжелее (Redis, celery). StarRocks/Doris дублировали бы Trino. |

Развёртывание — сервисы `metabase-plugin` и `metabase` в `docker-compose.yml`.

Действия в UI:

1. http://localhost:3000 → создать админа.
2. Add a database → тип **Starburst**.
3. Host `trino`, Port `8080`, Catalog `iceberg`, Username `trino`, SSL выкл.
4. Чтобы увидеть **Bronze**: schema `bronze`, вопрос `SELECT * FROM iceberg.bronze.customer LIMIT 50` или count по `lineitem`.
5. Для отчёта Q18: schema `gold`, таблица `q18_large_volume_customer`, bar chart по `totalprice`.

## 7. Выводы

Медальон разделяет ответственность: Bronze хранит полный TPC-H, Silver чистит (только qty>300), нормализует (`trim` имени) и обогащает (`volume_flag`), Gold отдаёт BI 57 строк без повторного shuffle 6 млн позиций. Parquet в MinIO + Iceberg REST (Lakekeeper) даёт схему, снапшоты и независимый compute (Trino), чего нет ни у «голого» S3, ни у одной Postgres на весь damп. На бенчмарке sf1 **GZIP** дал меньший Bronze (182.6 vs 187.7 МБ) и более быстрый Q18 (7.9 vs 16.6 с). Медальон всё равно на ZSTD — штатный кодек Iceberg; GZIP оставляю контрольной точкой. Запись ZSTD на `lineitem` в этом прогоне аномально долгая, вывод по CPU сжатия осторожный. Metabase подключён к тому же Trino-каталогу, поэтому витрина и сырой слой видны без выгрузки CSV.
