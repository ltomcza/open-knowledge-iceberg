---
type: PySpark Guide
title: Reading Data and Queries — Iceberg Tables in PySpark
description: Batch reads via spark.table/spark.read, time travel (VERSION AS OF, TIMESTAMP AS OF, snapshot-id/as-of-timestamp/branch/tag options), incremental reads, metadata tables (history, snapshots, files, manifests, partitions, entries), and system.* partition-transform SQL functions.
aliases: [iceberg time travel pyspark, VERSION AS OF, TIMESTAMP AS OF, iceberg snapshots table, iceberg metadata tables spark, incremental read iceberg, system.bucket spark sql, spark.table iceberg]
tags: [iceberg, pyspark, spark, queries, time-travel, metadata-tables, snapshots]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-queries
---

# Retrieval Notes

Read this for anything about reading/querying existing Iceberg tables:
plain SELECTs, time travel, incremental reads, or inspecting
snapshots/manifests/files. For writing data see
`/pyspark/writing-data.md`; for row-level upsert/CDC patterns see
`/pyspark/merge-into-and-row-level-operations.md`; for streaming reads see
`/pyspark/structured-streaming.md`. For partition-transform semantics in
depth see `/architecture/partitioning-and-hidden-partitioning.md`; for
snapshot lifecycle/expiry see `/maintenance/`.

# Summary

- Query by 3-part name `catalog.namespace.table`; metadata tables are
  addressed by suffixing the table name, e.g. `prod.db.table.snapshots`,
  `.history`, `.files`, `.manifests`, `.partitions`, `.entries`.
- Time travel in SQL: `VERSION AS OF <snapshot-id | 'branch' | 'tag'>` and
  `TIMESTAMP AS OF '<datetime>'` (also `FOR SYSTEM_VERSION/SYSTEM_TIME AS
  OF`). DataFrame reads use `.option("snapshot-id", ...)`,
  `.option("as-of-timestamp", ...)`, `.option("branch", ...)`, or
  `.option("tag", ...)`.
- Snapshot/timestamp time travel uses **the snapshot's schema**; branch time
  travel uses **the table's current schema** (with `NULL` for columns added
  after that snapshot); tag time travel uses **the tag's snapshot schema**.
- Incremental reads (`start-snapshot-id` exclusive, `end-snapshot-id`
  inclusive) only capture `append` operations — not
  `replace`/`overwrite`/`delete` — and are DataFrame-API-only, no SQL
  equivalent.
- `system.*` SQL functions (`system.bucket`, `system.years`, `system.days`,
  `system.hours`, `system.truncate`, `system.iceberg_version`) mirror
  partition transforms for use in filters; they only exist on an
  Iceberg-catalog-qualified call (`SparkCatalog`), not through
  `spark_catalog`/`SparkSessionCatalog` on Spark < 4.2.0.
- `content` in file/entry metadata tables: `0` = data, `1` = position
  deletes, `2` = equality deletes. `*_files`/`*_entries`/`*_manifests`
  reflect the current snapshot; `all_*` variants union across all tracked
  snapshots and may repeat rows.

# Querying with SQL

```python
spark.sql("SELECT * FROM prod.db.table")  # catalog: prod, namespace: db, table: table

# metadata tables use the table name as a namespace
spark.sql("SELECT * FROM prod.db.table.files").show()
```

## Spark SQL functions (`system.*`)

Available only through an Iceberg catalog (`SparkCatalog`), not registered
in Spark's built-in catalog. On Spark < 4.2.0, `spark_catalog.system.*`
fails even if `spark_catalog` uses `SparkSessionCatalog` (SPARK-54760) — use
a separate `SparkCatalog`-backed catalog to call them.

```python
spark.sql("SELECT system.iceberg_version()").show()
spark.sql("SELECT system.bucket(16, id), system.days(ts) FROM prod.db.table").show()

# explicit catalog qualification
spark.sql("SELECT prod.system.bucket(16, id) FROM prod.db.table").show()
```

Note: `PARTITIONED BY` uses singular transform names (`year(ts)`,
`month(ts)`); the SQL functions use plural names (`system.years(ts)`,
`system.months(ts)`).

| Function | Input types | Return type | Example |
|---|---|---|---|
| `system.iceberg_version()` | none | `string` | `SELECT system.iceberg_version();` |
| `system.bucket(numBuckets, col)` | date, tinyint, smallint, int, bigint, timestamp, timestamp_ntz, decimal, string, binary | `int` | `SELECT system.bucket(16, id) FROM prod.db.table;` |
| `system.years(col)` | date, timestamp, timestamp_ntz | `int` | `SELECT system.years(ts) FROM prod.db.table;` |
| `system.months(col)` | date, timestamp, timestamp_ntz | `int` | `SELECT system.months(ts) FROM prod.db.table;` |
| `system.days(col)` | date, timestamp, timestamp_ntz | `date` | `SELECT * FROM prod.db.table WHERE system.days(ts) = date('2025-03-01');` |
| `system.hours(col)` | timestamp, timestamp_ntz | `int` | `SELECT system.hours(ts) FROM prod.db.table;` |
| `system.truncate(width, col)` | tinyint, smallint, int, bigint, decimal, string, binary | same as `col` | `SELECT system.truncate(4, data) FROM prod.db.table;` |

All transform functions return `NULL` for `NULL` input.
`years`/`months`/`days`/`hours` return **transform values** (years since
1970-01-01, months since 1970-01, hours since 1970-01-01T00:00) not
extracted calendar fields; `days` returns a `date`. `truncate` rounds
numeric input down to the nearest multiple of `width`; for
string/binary it keeps the first `width` characters/bytes.

# Time Travel Queries with SQL

`VERSION AS OF` takes a snapshot ID or a branch/tag name string.
`TIMESTAMP AS OF` takes a timestamp string or Unix seconds.

```python
spark.sql("SELECT * FROM prod.db.table TIMESTAMP AS OF '1986-10-26 01:21:00'")
spark.sql("SELECT * FROM prod.db.table VERSION AS OF 10963874102873")
spark.sql("SELECT * FROM prod.db.table VERSION AS OF 'audit-branch'")     # head of branch
spark.sql("SELECT * FROM prod.db.table VERSION AS OF 'historical-snapshot'")  # tag

# ANSI-standard alternate syntax
spark.sql("SELECT * FROM prod.db.table FOR SYSTEM_TIME AS OF '1986-10-26 01:21:00'")
spark.sql("SELECT * FROM prod.db.table FOR SYSTEM_VERSION AS OF 10963874102873")
spark.sql("SELECT * FROM prod.db.table FOR SYSTEM_VERSION AS OF 'audit-branch'")

# Unix timestamp in seconds
spark.sql("SELECT * FROM prod.db.table TIMESTAMP AS OF 499162860")

# branch/tag as an identifier suffix (escape hyphenated names with backticks)
spark.sql("SELECT * FROM prod.db.table.`branch_audit-branch`")
spark.sql("SELECT * FROM prod.db.table.`tag_historical-snapshot`")
```

> If a branch/tag name coincides with a snapshot ID, `VERSION AS OF` on that
> string resolves to the snapshot ID, not the ref — rename with a
> well-defined prefix (e.g. `snapshot-1`) to avoid ambiguity. The
> `branch_<name>` / `tag_<name>` identifier form cannot be combined with
> `VERSION AS OF`.

## Schema selection during time travel

| Query form | Schema used |
|---|---|
| `TIMESTAMP AS OF '<ts>'` | the snapshot's schema at that time |
| `VERSION AS OF <snapshot-id>` | the snapshot's schema |
| `VERSION AS OF '<tag>'` / `` `tag_<name>` `` | the tag's snapshot schema |
| `VERSION AS OF '<branch>'` / `` `branch_<name>` `` | the **table's current** schema (columns added after the branched snapshot show `NULL` for older rows) |

```python
spark.sql("""
CREATE TABLE prod.db.orders (id BIGINT, status STRING) USING iceberg
""")
spark.sql("INSERT INTO prod.db.orders VALUES (1, 'NEW'), (2, 'PAID')")
# record this snapshot's id, e.g. 101

spark.sql("ALTER TABLE prod.db.orders ADD COLUMN total DOUBLE")
spark.sql("INSERT INTO prod.db.orders VALUES (3, 'PAID', 100.0)")

# snapshot/timestamp time travel -> only (id, status), 'total' not visible
spark.sql("SELECT * FROM prod.db.orders VERSION AS OF 101").show()

spark.sql("ALTER TABLE prod.db.orders CREATE BRANCH audit_branch AS OF VERSION 101")
spark.sql("ALTER TABLE prod.db.orders CREATE TAG first_load AS OF VERSION 101")

# branch -> current table schema (id, status, total); total is NULL for S1 rows
spark.sql("SELECT * FROM prod.db.orders VERSION AS OF 'audit_branch'").show()

# tag -> snapshot's own schema (id, status) only
spark.sql("SELECT * FROM prod.db.orders VERSION AS OF 'first_load'").show()
```

# Querying with DataFrames

```python
df = spark.table("prod.db.table")
```

## Table identifier resolution order (highest priority first)

| Form | Resolves to |
|---|---|
| `file:///path/to/table` | HadoopTable at that path |
| `catalog.tablename` | `tablename` from the named catalog |
| `catalog.namespace.tablename` | fully qualified |
| `namespace.tablename` | from current catalog |
| `namespace1.namespace2.tablename` | from current catalog |
| `tablename` | `currentCatalog.currentNamespace.tablename` |

```python
spark.read.format("iceberg").load("path/to/table")
spark.table("catalog.namespace.tablename")
```

## Time travel with the DataFrame API

Four read options; `branch` and `tag` cannot be combined with
`as-of-timestamp`.

```python
# as-of-timestamp (ms)
spark.read.option("as-of-timestamp", "499162860000").format("iceberg").load("path/to/table")

# snapshot-id
spark.read.option("snapshot-id", 10963874102873).format("iceberg").load("path/to/table")

# tag
spark.read.option("tag", "historical-snapshot").format("iceberg").load("path/to/table")

# branch
spark.read.option("branch", "audit-branch").format("iceberg").load("path/to/table")
```

## Incremental read

`start-snapshot-id` is exclusive, `end-snapshot-id` is inclusive (omit to
default to the current snapshot). Only captures `append` operations — not
`replace`/`overwrite`/`delete`. Works with both format-version 1 and 2.
**No SQL equivalent** — DataFrame API only.

```python
spark.read \
    .format("iceberg") \
    .option("start-snapshot-id", "10963874102873") \
    .option("end-snapshot-id", "63874143573109") \
    .load("path/to/table")
```

# Inspecting Tables (Metadata Tables)

Addressed as `<table>.<metadata-table-name>`.

| Metadata table | Shows |
|---|---|
| `.history` | `made_current_at`, `snapshot_id`, `parent_id`, `is_current_ancestor` — full snapshot lineage including rolled-back commits |
| `.metadata_log_entries` | `timestamp`, `file`, `latest_snapshot_id`, `latest_schema_id`, `latest_sequence_number` — metadata.json history |
| `.snapshots` | `committed_at`, `snapshot_id`, `parent_id`, `operation`, `manifest_list`, `summary` |
| `.entries` | manifest entries (data + delete files) for the current snapshot: `status`, `snapshot_id`, `sequence_number`, `file_sequence_number`, `data_file`, `readable_metrics` |
| `.files` | current data + delete files with stats: `content` (0=data,1=position-delete,2=equality-delete), `file_path`, `file_format`, `record_count`, `column_sizes`, `null_value_counts`, `lower_bounds`/`upper_bounds`, `readable_metrics`, etc. |
| `.data_files` / `.delete_files` | current data files only / delete files only |
| `.manifests` | `content`, `path`, `length`, `partition_spec_id`, `added_snapshot_id`, `added/existing/deleted_data_files_count`, `partition_summaries` |
| `.partitions` | `partition`, `spec_id`, `record_count`, `file_count`, `total_data_file_size_in_bytes`, delete counts, `last_updated_at`, `last_updated_snapshot_id` |
| `.position_deletes` | `file_path`, `pos`, `row`, `partition`, `spec_id`, `delete_file_path` — positional delete detail |
| `.all_entries` / `.all_data_files` / `.all_delete_files` / `.all_manifests` | union across **all** tracked snapshots (may repeat rows per file) |
| `.refs` | `name`, `type` (BRANCH/TAG), `snapshot_id`, `max_reference_age_in_ms`, `min_snapshots_to_keep`, `max_snapshot_age_in_ms` |

```python
spark.sql("SELECT * FROM prod.db.table.history").show()
spark.sql("SELECT * FROM prod.db.table.snapshots").show()
spark.sql("SELECT * FROM prod.db.table.files").show()
spark.sql("SELECT * FROM prod.db.table.manifests").show()
spark.sql("SELECT * FROM prod.db.table.partitions").show()
spark.sql("SELECT * FROM prod.db.table.entries").show()
spark.sql("SELECT * FROM prod.db.table.refs").show()

# join history to snapshots, e.g. to see which application wrote each snapshot
spark.sql("""
SELECT
    h.made_current_at,
    s.operation,
    h.snapshot_id,
    h.is_current_ancestor,
    s.summary['spark.app.id']
FROM prod.db.table.history h
JOIN prod.db.table.snapshots s
  ON h.snapshot_id = s.snapshot_id
ORDER BY made_current_at
""").show()
```

For unpartitioned tables, `.partitions` omits `partition`/`spec_id`. The
`.partitions` table only reflects partitions with files in the current
snapshot; delete files are not applied, so a partition may still appear
even if all its rows are logically deleted.

## Inspecting with DataFrames

```python
spark.read.format("iceberg").load("db.table.files")                      # named metastore table
spark.read.format("iceberg").load("hdfs://nn:8020/path/to/table#files")  # Hadoop path table
```

## Time travel on metadata tables

```python
spark.sql("SELECT * FROM prod.db.table.manifests TIMESTAMP AS OF '2021-09-20 08:00:00'")
spark.sql("SELECT * FROM prod.db.table.partitions VERSION AS OF 10963874102873")

spark.read.format("iceberg").option("snapshot-id", 10963874102873).load("db.table.files")
```

# Citations

[1] [Spark Queries](https://iceberg.apache.org/docs/latest/spark-queries)
