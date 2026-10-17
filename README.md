# Lakehouse TPC-H Q18 — Large Volume Customer

Локальный lakehouse (MinIO + PostgreSQL + Lakekeeper + Trino + Metabase) и полный медальон Bronze → Silver → Gold по варианту 3, TPC-H Query 18.

Отчёт для преподавателя: [`отчет.md`](отчет.md).

Образы `minio/minio` с Docker Hub сняты; сервис `minio` в compose идёт с публичным S3 drop-in `pgsty/silo` (тот же API и консоль).

## Быстрый старт

```bash
docker compose up -d
./scripts/wait_trino.sh
./scripts/pipeline.sh      # sf1: Bronze/Silver/Gold + schema evolution + time travel
./scripts/benchmark.sh     # GZIP vs ZSTD на Bronze + время Q18
docker compose --profile bi up -d   # Metabase :3000, после загрузки данных
```

Docker Desktop лучше отдать ≥ 8 ГБ RAM. На 4 ГБ стек живёт без Metabase во время ETL (профиль `bi`).

Сервисы:

| URL | Что |
|---|---|
| http://localhost:9001 | S3-консоль MinIO/Silo (`minioadmin` / `minioadmin123`) |
| http://localhost:8181 | Lakekeeper UI (Iceberg REST Catalog) |
| http://localhost:8080 | Trino |
| http://localhost:3000 | Metabase |

Остановка: `docker compose down`. Данные в named volumes (`minio_data`, `pg_data`, `metabase_data`).

## Что делает Q18

Клиенты и заказы, у которых суммарное количество товара в `lineitem` **> 300**. Результат — **топ-100** по `totalprice`.

Таблицы: `customer ⋈ orders ⋈ lineitem` + подзапрос по `lineitem`.

## Медальон

```
tpch.sf1.*  ──CTAS──►  Bronze (сырые customer/orders/lineitem, Parquet+ZSTD)
                         │
                         ├─► Silver.large_orders     (HAVING sum(quantity) > 300)
                         └─► Silver.q18_joined       (join + trim имени, partition year(orderdate))
                                   │
                                   └─► Gold.q18_large_volume_customer  (топ-100)
```

SQL лежит в `sql/`. Команды запуска — в `scripts/`.

## Metabase поверх Bronze

1. Открыть http://localhost:3000, пройти wizard.
2. Add database → **Starburst** / Trino:
   - Host: `trino`
   - Port: `8080`
   - Catalog: `iceberg`
   - Schema: `bronze`
   - User: `trino` (без пароля)
3. В SQL editor:

```sql
SELECT count(*) FROM iceberg.bronze.lineitem;
SELECT * FROM iceberg.bronze.customer LIMIT 20;
```

Драйвер Starburst кладётся в `/plugins` контейнера сервисом `metabase-plugin`.

## Time travel (восстановление чтением снапшота)

После пайплайна на Silver есть UPDATE `volume_flag`. Предыдущий снимок:

```sql
SELECT snapshot_id, parent_id, committed_at, operation
FROM iceberg.silver."q18_joined$snapshots";

SELECT *
FROM iceberg.silver.q18_joined
FOR VERSION AS OF <parent_snapshot_id>;
```

Чтобы **откатить таблицу** на снапшот (а не только прочитать):

```sql
CALL iceberg.system.rollback_to_snapshot('silver', 'q18_joined', <snapshot_id>);
```

## Структура репозитория

```
docker-compose.yml
lakekeeper/create-warehouse.json
trino/catalog/{iceberg,tpch}.properties
sql/
scripts/{up,pipeline,benchmark,trino,wait_trino}.sh
отчет.md
```
