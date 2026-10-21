---
type: PySpark Guide
title: Writing Data to Iceberg Tables in PySpark
description: DataFrame writes via writeTo (append, overwritePartitions, overwrite, create/replace/createOrReplace), INSERT INTO / INSERT OVERWRITE via SQL, dynamic vs static partition overwrite, writing to branches, distribution modes, and file-size control.
aliases: [df.writeTo iceberg, insert overwrite iceberg, dynamic partition overwrite, iceberg write distribution mode, overwritePartitions pyspark, spark.sql.sources.partitionOverwriteMode, iceberg fanout writer, write.target-file-size-bytes]
tags: [iceberg, pyspark, spark, writes, dataframe, insert, overwrite, partitioning]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-writes
---

# Retrieval Notes

Read this for appending/overwriting/creating Iceberg tables from PySpark —
plain inserts and overwrites, not upserts. For `MERGE INTO`, `UPDATE`, and
`DELETE FROM` (row-level operations, upsert/CDC patterns) see
`/pyspark/merge-into-and-row-level-operations.md`. For DDL/CTAS syntax
itself see `/pyspark/ddl-create-alter-tables.md`. For compaction and small
file cleanup after heavy write/overwrite workloads see
`/maintenance/compaction-and-file-sizing.md`. For branch/tag DDL see
`/pyspark/ddl-create-alter-tables.md#branches-and-tags`.

# Summary

- **`DataFrameWriterV2`** (`df.writeTo(...)`) is the recommended write API:
  operations write columns by name, hidden-partition transforms are
  supported in `partitionedBy`, and overwrite behavior is explicit
  (dynamic or filter-based) — unlike the legacy v1 `write` API, which is
  still supported but discouraged.
- `df.writeTo(t).create()` ≈ `CREATE TABLE AS SELECT`; `.replace()` ≈
  `REPLACE TABLE AS SELECT`; `.append()` ≈ `INSERT INTO`;
  `.overwritePartitions()` ≈ dynamic `INSERT OVERWRITE`.
- **Dynamic partition overwrite mode is recommended** for Iceberg tables
  (`spark.sql.sources.partitionOverwriteMode=dynamic`) — it replaces
  exactly the partitions produced by the `SELECT`/DataFrame, including
  hidden partitions. Spark's **default is static** mode, which converts
  the `PARTITION` clause (or its absence) to a delete filter and can only
  reference actual table columns, not hidden partition transforms.
- **`MERGE INTO` is recommended over `INSERT OVERWRITE`** in general,
  because it rewrites only the affected data files and its behavior does
  not shift when the table's partition spec evolves.
- `write.distribution-mode` (table property) controls how Spark clusters
  rows across tasks before writing: `none` (no auto shuffle/sort — you
  must manually sort or accept many small files/open handles), `hash`
  (default since Iceberg 1.2.0 — hash-shuffle by partition value), `range`
  (two-stage sample + range-shuffle; also globally sorts, used by default
  when the table has a sort order).
- A Spark task cannot produce a file that spans an Iceberg partition
  boundary or exceeds task size; on-disk (compressed, columnar) file size
  is typically much smaller than in-memory task size, so
  `spark.sql.adaptive.advisoryPartitionSizeInBytes` usually needs to be
  set larger than the target on-disk file size.
- Writing to a branch requires the branch to already exist (writes never
  create it); target it as `<table>.branch_<name>`, or use `spark.wap.branch`
  for a write-audit-publish workflow — the two cannot be combined.

# Feature Support (Spark DSv2)

| Feature | Support | Notes |
|---|---|---|
| SQL `INSERT INTO` | Yes | Requires `spark.sql.storeAssignmentPolicy=ANSI` (default since Spark 3.0) |
| SQL `MERGE INTO` | Yes | Requires Iceberg Spark extensions — see merge-into file |
| SQL `INSERT OVERWRITE` | Yes | Requires `spark.sql.storeAssignmentPolicy=ANSI` |
| SQL `DELETE FROM` | Yes | Row-level delete requires Iceberg Spark extensions — see merge-into file |
| SQL `UPDATE` | Yes | Requires Iceberg Spark extensions — see merge-into file |
| DataFrame append | Yes | |
| DataFrame overwrite | Yes | |
| DataFrame CTAS / RTAS | Yes | Requires DSv2 API |
| DataFrame merge into | Yes | Requires DSv2 API (Spark 4.0+) — see merge-into file |

# INSERT INTO (SQL)

```python
spark.sql("INSERT INTO prod.db.table VALUES (1, 'a'), (2, 'b')")
spark.sql("INSERT INTO prod.db.table SELECT ...")
```

# INSERT OVERWRITE (SQL)

Atomic for Iceberg tables. Which partitions get replaced depends on
Spark's partition overwrite mode and the table's partitioning.

## Dynamic overwrite (recommended)

```python
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
```

Only partitions that appear in the `SELECT` result are replaced —
including hidden partitions (e.g. `hours(ts)`).

```python
spark.sql("""
CREATE TABLE prod.my_app.logs (
    uuid string NOT NULL,
    level string NOT NULL,
    ts timestamp NOT NULL,
    message string)
USING iceberg
PARTITIONED BY (level, hours(ts))
""")

# dedupe events for 2020-07-01; in dynamic mode only the hour-partitions
# touched by rows with that date are replaced
spark.sql("""
INSERT OVERWRITE prod.my_app.logs
SELECT uuid, first(level), first(ts), first(message)
FROM prod.my_app.logs
WHERE cast(ts as date) = '2020-07-01'
GROUP BY uuid
""")
```

## Static overwrite (Spark default)

The `PARTITION` clause becomes a delete filter; it can only reference
actual table columns, never hidden partition transforms. Omitting
`PARTITION` replaces **all** rows in the table.

```python
spark.sql("""
INSERT OVERWRITE prod.my_app.logs
PARTITION (level = 'INFO')
SELECT uuid, first(level), first(ts), first(message)
FROM prod.my_app.logs
WHERE level = 'INFO'
GROUP BY uuid
""")
```

This static example cannot replace hourly (hidden) partitions the way the
dynamic example does, because `PARTITION` only sees real columns.

# Writing to Branches

The branch must already exist (create it via
`ALTER TABLE ... CREATE BRANCH`, see
`/pyspark/ddl-create-alter-tables.md`) — writes never create a branch
implicitly. Writing to a branch validates against the table's **current**
schema.

## Via SQL

```python
# INSERT into the 'audit' branch
spark.sql("INSERT INTO prod.db.table.branch_audit VALUES (1, 'a'), (2, 'b')")

# Write-Audit-Publish (WAP): route writes into a branch via config instead
spark.conf.set("spark.wap.branch", "audit-branch")
spark.sql("INSERT INTO prod.db.table VALUES (3, 'c')")
```

> `spark.wap.branch` and an explicit `branch_<name>` identifier cannot be
> used together. `MERGE INTO`, `UPDATE`, and `DELETE FROM` also accept the
> `<table>.branch_<name>` target — see
> `/pyspark/merge-into-and-row-level-operations.md`.

## Via DataFrames

```python
data.writeTo("prod.db.table.branch_audit").append()          # insert into 'audit' branch
data.writeTo("prod.db.table.branch_audit").overwritePartitions()  # dynamic overwrite on 'audit' branch
```

# Writing with DataFrames (DataFrameWriterV2)

```python
from pyspark.sql import functions as F
```

> **v1 API danger:** if you must use the legacy `df.write` API, use
> `saveAsTable`/`insertInto` to resolve tables through a catalog.
> `df.write.format("iceberg")` loads an isolated table reference that will
> not auto-refresh alongside other queries using the same table.

## Appending data

```python
data.writeTo("prod.db.table").append()
```

## Overwriting data

```python
# dynamic overwrite: replace every partition touched by rows in `data`
data.writeTo("prod.db.table").overwritePartitions()

# explicit overwrite: replace only rows matching a filter condition
data.writeTo("prod.db.table").overwrite(F.col("level") == "INFO")
```

Neither call checks for concurrent changes by default (the `isolation-level`
write option defaults to `null`). For conflict-safe overwrites, empty-input
pitfalls, and the SQL equivalent `INSERT INTO ... REPLACE WHERE` (Spark 3.4+),
see
[/performance/full-partition-rewrite-and-safe-overwrite.md](/performance/full-partition-rewrite-and-safe-overwrite.md).

## Creating tables (CTAS / RTAS)

```python
data.writeTo("prod.db.table").create()          # CTAS
data.writeTo("prod.db.table").replace()         # RTAS
data.writeTo("prod.db.table").createOrReplace()
```

If `spark_catalog` has been replaced with Iceberg's `SparkSessionCatalog`,
specify the provider explicitly:

```python
data.writeTo("db.table").using("iceberg").create()
```

`create`/`replace`/`createOrReplace` support table configuration:

```python
data.writeTo("prod.db.table") \
    .tableProperty("write.format.default", "orc") \
    .partitionedBy(F.col("level"), F.days("ts")) \
    .createOrReplace()
```

`partitionedBy` accepts plain columns (identity partitioning) or only
these transform functions from `pyspark.sql.functions`: `years()`,
`months()`, `days()`, `hours()`, `bucket()`.

Set the table location via the `location` table property:

```python
data.writeTo("prod.db.table") \
    .tableProperty("location", "/path/to/location") \
    .createOrReplace()
```

# Schema Merge (Automatic Schema Evolution on Write)

When enabled, Iceberg reconciles a mismatched write schema against the
table schema:

- Column present in source but not target → added to the table; existing
  rows get `NULL` for it.
- Column present in target but not source → `NULL` on insert for new
  rows; left unchanged on update for existing rows.

Requires the table to opt in, plus a per-write option:

```python
spark.sql("""
ALTER TABLE prod.db.sample SET TBLPROPERTIES (
  'write.spark.accept-any-schema'='true'
)
""")

data.writeTo("prod.db.sample").option("mergeSchema", "true").append()
```

# Writing Distribution Modes

Iceberg's default Spark writers require rows within each Spark task to be
clustered by partition value (to limit open file handles). Since Iceberg
1.2.0, Iceberg also requests Spark pre-sort data to match this via the
table property `write.distribution-mode` (default `hash`). Spark did not
respect distribution mode in CTAS/RTAS before 3.5.0.

```python
spark.sql("""
CREATE TABLE prod.db.sample (
    id bigint,
    data string,
    category string,
    ts timestamp)
USING iceberg
PARTITIONED BY (days(ts), category)
""")

# hash distribution automatically clusters rows by (days(ts), category)
# before writing — no manual sort needed
spark.sql("INSERT INTO prod.db.sample SELECT id, data, category, ts FROM another_table")
```

| Mode | Behavior |
|---|---|
| `none` | No automatic shuffle/sort (legacy default). Data must be manually sorted by partition value (per-task or globally) to avoid excess open file handles; a global sort minimizes output file count. Can also avoid sorting via the write `fanout-enabled` option, at the cost of holding every file handle open until the task completes. |
| `hash` | Default since 1.2.0. Rows are hash-shuffled by partition value into corresponding Spark tasks; Adaptive Query Execution may further split/coalesce tasks. |
| `range` | Two-stage: samples data by partition+sort columns, then range-shuffles so each task gets an exclusive, globally-sorted range. More expensive than `hash` but improves read performance when queries filter/sort on those columns. Default when the table has a defined sort order. |

# Controlling File Sizes

A Spark task cannot produce a file that spans an Iceberg partition
boundary, and Iceberg only rolls a file over at
`write.target-file-size-bytes` if the task itself is large enough to reach
that size. On-disk files (compressed, columnar) are typically much
smaller than the in-memory Spark task that produced them — more so if that
task writes into multiple partitions.

- Use a `write.distribution-mode` (above) or manual repartitioning to
  control what ends up in each Spark task.
- Tune Spark's Adaptive Query Execution — when `write.distribution-mode`
  isn't `none`, AQE coalesces/splits tasks toward
  `spark.sql.adaptive.advisoryPartitionSizeInBytes` during the write
  shuffle (this also affects manual repartitions/sorts). Because this is
  in-memory row size, not on-disk compressed size, set it noticeably
  larger than your actual `write.target-file-size-bytes` target — the
  right ratio is data-dependent.

For post-write file-size remediation (compaction), see
`/maintenance/compaction-and-file-sizing.md`.

# Citations

[1] [Spark Writes](https://iceberg.apache.org/docs/latest/spark-writes)
[2] [pyspark.sql.DataFrameWriterV2.partitionedBy](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.html)
[3] [pyspark.sql.DataFrameWriterV2.overwrite](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.overwrite.html)
