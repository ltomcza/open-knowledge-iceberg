---
type: Tutorial
title: 5. Upsert, MERGE INTO, and CDC
description: Build a staging DataFrame of updates, inserts, and deletes, then apply it to a target table in one atomic MERGE INTO statement.
aliases: [iceberg merge into pyspark, iceberg upsert, iceberg when matched when not matched, iceberg cdc example]
tags: [tutorial, pyspark, merge-into, upsert, cdc, intermediate]
timestamp: 2026-07-31T00:00:00Z
difficulty: intermediate
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) through
[4. Time Travel and Rollback](/tutorials/04-time-travel-and-rollback.md). This tutorial creates its
own fresh table.

# What You'll Learn

- How to model a batch of "changed" rows — some updates, some new inserts, one deletion — as a
  plain PySpark DataFrame, the way you'd receive it from a CDC feed or a daily extract.
- How to apply that whole batch to a target table atomically with `MERGE INTO`, using
  `WHEN MATCHED` and `WHEN NOT MATCHED` clauses.
- Why `MERGE INTO` is the recommended way to do this in Iceberg, rather than `INSERT OVERWRITE`.

# Steps

## 1. Set up Spark and create a target table with some existing data

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("iceberg-tutorial")
    .config("spark.jars.packages", "org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.local.type", "hadoop")
    .config("spark.sql.catalog.local.warehouse", "/tmp/warehouse")
    .config("spark.sql.defaultCatalog", "local")
    .getOrCreate()
)

spark.sql("CREATE NAMESPACE IF NOT EXISTS db")
spark.sql("DROP TABLE IF EXISTS local.db.customers PURGE")
spark.sql("""
    CREATE TABLE local.db.customers (
        id     bigint,
        name   string,
        email  string,
        status string
    )
    USING iceberg
""")

spark.sql("""
    INSERT INTO local.db.customers VALUES
        (1, 'Ada Lovelace',     'ada@example.com',       'active'),
        (2, 'Grace Hopper',     'grace@example.com',     'active'),
        (3, 'Katherine Johnson','katherine@example.com', 'active')
""")

spark.sql("SELECT * FROM local.db.customers ORDER BY id").show()
```

**Expected output:** three existing customer rows, all `active`.

## 2. Build a staging DataFrame of changes

This represents a batch of changes you might receive from an upstream system: an email update for
an existing customer, a brand-new customer, and a deletion flag for a customer who unsubscribed.

```python
from pyspark.sql import Row

changes = spark.createDataFrame([
    # Existing customer, email changed -> should UPDATE
    Row(id=2, name="Grace Hopper", email="grace.hopper@example.com", status="active", op="upsert"),
    # Brand-new customer -> should INSERT
    Row(id=4, name="Margaret Hamilton", email="margaret@example.com", status="active", op="upsert"),
    # Existing customer, unsubscribed -> should DELETE
    Row(id=3, name="Katherine Johnson", email="katherine@example.com", status="active", op="delete"),
])

changes.createOrReplaceTempView("staged_changes")
changes.show()
```

**Expected output:** the three staged rows, including the `op` column that flags each row's intent.

## 3. Apply the batch with `MERGE INTO`

```python
spark.sql("""
    MERGE INTO local.db.customers AS t
    USING staged_changes AS s
    ON t.id = s.id
    WHEN MATCHED AND s.op = 'delete' THEN
        DELETE
    WHEN MATCHED AND s.op = 'upsert' THEN
        UPDATE SET t.name = s.name, t.email = s.email, t.status = s.status
    WHEN NOT MATCHED AND s.op = 'upsert' THEN
        INSERT (id, name, email, status) VALUES (s.id, s.name, s.email, s.status)
""")
```

**Expected output:** no errors. This one statement rewrote only the data files that actually
contain affected rows — Iceberg does not rewrite the whole table.

## 4. Verify the result

```python
spark.sql("SELECT * FROM local.db.customers ORDER BY id").show()
```

**Expected output:**

```
+---+-----------------+-------------------------+------+
| id|             name|                    email|status|
+---+-----------------+-------------------------+------+
|  1|     Ada Lovelace|          ada@example.com|active|
|  2|     Grace Hopper|grace.hopper@example.com |active|
|  4|Margaret Hamilton|    margaret@example.com |active|
+---+-----------------+-------------------------+------+
```

`id=1` is untouched (it wasn't in the staging batch), `id=2`'s email was updated, `id=3` was
deleted, and `id=4` was inserted as a new row — all from a single atomic commit, visible as one new
snapshot:

```python
spark.sql("SELECT operation, summary FROM local.db.customers.snapshots ORDER BY committed_at DESC LIMIT 1").show(truncate=False)
```

**Expected output:** the most recent snapshot's `operation` is `overwrite`, and its `summary` map
includes counts like `changed-partition-count` reflecting the merge.

# Common Pitfalls

- **Only one source row per target row.** If your staging data has two rows that both match the
  same target row on the `ON` condition, `MERGE INTO` throws an error rather than silently picking
  one — deduplicate the source (e.g. keep the latest change per `id`) before merging.
- **Using `INSERT OVERWRITE` instead.** It's tempting for "replace everything that changed", but
  `MERGE INTO` is recommended because it only rewrites the specific files containing affected rows,
  and its behavior doesn't shift if the table's partitioning changes later — `INSERT OVERWRITE`'s
  dynamic-partition behavior does.
- **Forgetting a catch-all condition.** Multiple `WHEN MATCHED` clauses are evaluated in order and
  the first match wins; if none of your conditions match a matched row, nothing happens to it
  (which is sometimes what you want, but verify it's intentional).
- **Not registering the staging DataFrame as a temp view.** `MERGE INTO ... USING (SELECT ...)`
  needs a queryable relation; `df.createOrReplaceTempView(...)` (as used above) is the simplest way
  to make a DataFrame usable from SQL.

# Next Steps

Continue to [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md) — repeated
small merges and appends are exactly what leads to the "small file problem" covered there.

For the full `MERGE INTO` syntax reference (multiple clauses, `NOT MATCHED BY SOURCE`, the
DataFrame `mergeInto()` API), see
[/pyspark/merge-into-and-row-level-operations.md](/pyspark/merge-into-and-row-level-operations.md).

# Citations

[1] [Spark Writes — MERGE INTO syntax](https://iceberg.apache.org/docs/latest/spark-writes/)
[2] [Spark Procedures — create_changelog_view (for CDC-style change tracking)](https://iceberg.apache.org/docs/latest/spark-procedures/)
