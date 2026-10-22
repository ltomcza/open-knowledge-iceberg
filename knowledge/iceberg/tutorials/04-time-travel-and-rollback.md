---
type: Tutorial
title: 4. Time Travel and Rollback
description: Make a sequence of changes to a table, list its snapshot history, query an earlier state with VERSION AS OF and TIMESTAMP AS OF, and roll back with a stored procedure.
aliases: [iceberg time travel, iceberg version as of, iceberg rollback_to_snapshot, iceberg snapshot history]
tags: [tutorial, pyspark, time-travel, snapshots, rollback, intermediate]
timestamp: 2026-10-22T00:00:00Z
difficulty: intermediate
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) through
[3. Schema and Partition Evolution](/tutorials/03-schema-and-partition-evolution.md). This tutorial
creates its own fresh table.

# What You'll Learn

- That every write to an Iceberg table creates a new immutable **snapshot**, and how to list that
  history with the `.history` and `.snapshots` metadata tables.
- How to query the table as it looked at an earlier point, using `VERSION AS OF` (by snapshot ID)
  and `TIMESTAMP AS OF` (by wall-clock time).
- How to permanently roll a table back to an earlier snapshot with
  `CALL system.rollback_to_snapshot(...)`.

# Steps

## 1. Set up Spark and build up some history

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("iceberg-tutorial")
    .config("spark.jars.packages", "org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.12.0")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.local.type", "hadoop")
    .config("spark.sql.catalog.local.warehouse", "/tmp/warehouse")
    .config("spark.sql.defaultCatalog", "local")
    .getOrCreate()
)

spark.sql("CREATE NAMESPACE IF NOT EXISTS db")
spark.sql("DROP TABLE IF EXISTS local.db.orders PURGE")
spark.sql("""
    CREATE TABLE local.db.orders (
        id     bigint,
        status string
    )
    USING iceberg
""")

import time

# Snapshot 1: initial load
spark.sql("INSERT INTO local.db.orders VALUES (1, 'NEW'), (2, 'NEW')")
time.sleep(1)

# Snapshot 2: another batch arrives
spark.sql("INSERT INTO local.db.orders VALUES (3, 'NEW')")
time.sleep(1)

# Snapshot 3: order 1 ships
spark.sql("UPDATE local.db.orders SET status = 'SHIPPED' WHERE id = 1")
time.sleep(1)

# Snapshot 4: order 2 is cancelled and removed
spark.sql("DELETE FROM local.db.orders WHERE id = 2")

spark.sql("SELECT * FROM local.db.orders ORDER BY id").show()
```

**Expected output:** the current state, two rows — `id=1` with status `SHIPPED`, and `id=3` with
status `NEW` (`id=2` was deleted). Four snapshots have been created along the way. The `time.sleep`
calls just keep snapshot timestamps clearly separated for this tutorial.

## 2. List the snapshot history

```python
history_df = spark.sql("SELECT * FROM local.db.orders.history ORDER BY made_current_at")
history_df.show(truncate=False)

snapshots = spark.sql("SELECT * FROM local.db.orders.snapshots ORDER BY committed_at").collect()
for row in snapshots:
    print(row["snapshot_id"], row["operation"], row["committed_at"])
```

**Expected output:** four rows in `.history` (one per commit above), and four snapshots printed with
their `operation` field showing `append`, `append`, `overwrite` (the `UPDATE`), and `overwrite`
(the `DELETE`) in order — your actual snapshot IDs and timestamps will differ from any example
shown elsewhere, since they're generated at run time.

## 3. Query an earlier state with `VERSION AS OF`

Grab the ID of the very first snapshot programmatically (don't hardcode it — it's random per run):

```python
first_snapshot_id = snapshots[0]["snapshot_id"]
print(f"First snapshot: {first_snapshot_id}")

spark.sql(f"SELECT * FROM local.db.orders VERSION AS OF {first_snapshot_id}").show()
```

**Expected output:**

```
+---+------+
| id|status|
+---+------+
|  1|   NEW|
|  2|   NEW|
+---+------+
```

This is the table exactly as it looked right after the first `INSERT INTO` — before the update and
delete ever happened.

## 4. Query an earlier state with `TIMESTAMP AS OF`

```python
second_snapshot_ts = snapshots[1]["committed_at"]
ts_string = second_snapshot_ts.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
print(f"Traveling to: {ts_string}")

spark.sql(f"SELECT * FROM local.db.orders TIMESTAMP AS OF '{ts_string}'").show()
```

**Expected output:**

```
+---+------+
| id|status|
+---+------+
|  1|   NEW|
|  2|   NEW|
|  3|   NEW|
+---+------+
```

This reflects the table right after the second snapshot (three rows, all still `NEW`) — before the
update and delete.

## 5. Roll back permanently with `rollback_to_snapshot`

Time travel queries above don't change the table — they just read an older state. To actually make
an earlier snapshot the table's **current** state, use the stored procedure:

```python
result = spark.sql(f"""
    CALL local.system.rollback_to_snapshot('db.orders', {first_snapshot_id})
""")
result.show(truncate=False)

spark.sql("SELECT * FROM local.db.orders ORDER BY id").show()
```

**Expected output:** the `CALL` result shows `previous_snapshot_id` and `current_snapshot_id`
columns; the second `SELECT` now shows the table back to its very first state (`id=1` and `id=2`,
both `NEW`) as the **live** table, not just a time-travel query.

# Common Pitfalls

- **Hardcoding snapshot IDs.** Snapshot IDs are randomly generated per commit — they will be
  different every time you run this tutorial. Always capture them programmatically from
  `.snapshots` or `.history`, as done above, rather than copying a number from an example.
- **Confusing a time-travel `SELECT` with a rollback.** `VERSION AS OF` / `TIMESTAMP AS OF` are
  read-only — they don't change what "current" means for the table. Only
  `CALL system.rollback_to_snapshot(...)` (or `set_current_snapshot`) changes the table's current
  pointer.
- **Rolling back to a non-ancestor snapshot.** `rollback_to_snapshot` requires the target to be an
  ancestor of the current snapshot. If you need to jump to any arbitrary snapshot (including one on
  an abandoned branch), use `CALL system.set_current_snapshot(...)` instead.
- **Assuming rolled-back data is gone forever.** It isn't, immediately — the snapshots you rolled
  back past are still in the table's metadata and their data files are still on disk until they're
  expired (see [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md)). This
  is exactly what makes rollback safe.

# Next Steps

Continue to [5. Upsert, MERGE INTO, and CDC](/tutorials/05-upsert-merge-and-cdc.md) to apply changes
from a staging dataset in one atomic operation.

For the concepts behind snapshots, see
[/architecture/snapshots-and-versioning.md](/architecture/snapshots-and-versioning.md).

# Citations

[1] [Spark Queries — Time Travel Queries with SQL](https://iceberg.apache.org/docs/latest/spark-queries/)
[2] [Spark Queries — History, Snapshots, and other metadata tables](https://iceberg.apache.org/docs/latest/spark-queries/)
[3] [Spark Procedures — rollback_to_snapshot, rollback_to_timestamp, set_current_snapshot](https://iceberg.apache.org/docs/latest/spark-procedures/)
