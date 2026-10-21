---
type: Tutorial
title: 2. Your First Table - Create, Insert, Read
description: Create a namespace and table, write data with both SQL and a PySpark DataFrame, read it back, and see the resulting files on disk.
aliases: [create iceberg table pyspark, iceberg insert into, iceberg writeTo append, iceberg crud tutorial]
tags: [tutorial, pyspark, ddl, writes, reads, beginner]
timestamp: 2026-07-31T00:00:00Z
difficulty: beginner
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) first — you need PySpark, the
Iceberg runtime, and the local `local` catalog pointed at `/tmp/warehouse` working before starting
here.

# What You'll Learn

- How to create a namespace and an Iceberg table with `CREATE TABLE ... USING iceberg`.
- How to write data both with SQL (`INSERT INTO`) and with the DataFrame v2 API (`df.writeTo(...).append()`).
- How to read a table back with SQL and with `spark.table(...)`.
- How to look at what Iceberg actually put on disk — the metadata and data file layout — so the
  abstract description in [/architecture/table-format-overview.md](/architecture/table-format-overview.md)
  becomes something you've seen with your own eyes.

# Steps

## 1. Start Spark with the Iceberg catalog

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
```

**Expected output:** no errors; `spark` is now a working `SparkSession`.

## 2. Create a namespace and a table

```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS db")

spark.sql("""
    CREATE TABLE IF NOT EXISTS local.db.people (
        id     bigint,
        name   string,
        email  string
    )
    USING iceberg
""")

spark.sql("DESCRIBE TABLE local.db.people").show(truncate=False)
```

**Expected output:**

```
+---------+---------+-------+
|col_name |data_type|comment|
+---------+---------+-------+
|id       |bigint   |null   |
|name     |string   |null   |
|email    |string   |null   |
+---------+---------+-------+
```

## 3. Insert data with SQL

```python
spark.sql("""
    INSERT INTO local.db.people VALUES
        (1, 'Ada Lovelace', 'ada@example.com'),
        (2, 'Grace Hopper', 'grace@example.com')
""")

spark.sql("SELECT * FROM local.db.people ORDER BY id").show()
```

**Expected output:**

```
+---+-------------+------------------+
| id|         name|             email|
+---+-------------+------------------+
|  1| Ada Lovelace|   ada@example.com|
|  2| Grace Hopper| grace@example.com|
+---+-------------+------------------+
```

## 4. Insert data with a DataFrame (`writeTo().append()`)

The DataFrame v2 write API is the recommended way to write from PySpark code (as opposed to
constructing SQL strings):

```python
from pyspark.sql import Row

new_rows = spark.createDataFrame([
    Row(id=3, name="Katherine Johnson", email="katherine@example.com"),
    Row(id=4, name="Margaret Hamilton", email="margaret@example.com"),
])

new_rows.writeTo("local.db.people").append()

spark.sql("SELECT * FROM local.db.people ORDER BY id").show()
```

**Expected output:**

```
+---+-----------------+----------------------+
| id|             name|                 email|
+---+-----------------+----------------------+
|  1|     Ada Lovelace|       ada@example.com|
|  2|     Grace Hopper|     grace@example.com|
|  3|Katherine Johnson|katherine@example.com|
|  4|Margaret Hamilton| margaret@example.com|
+---+-----------------+----------------------+
```

## 5. Read the table as a DataFrame

```python
df = spark.table("local.db.people")
print(df.count())
df.show()
```

**Expected output:** `4`, followed by the same four rows shown above (order is not guaranteed
without an `ORDER BY`, since Spark reads data files in parallel).

## 6. Look at the files Iceberg actually wrote

Every `INSERT INTO` / `append()` call created a new **snapshot**, and each snapshot points at new
data files tracked through manifests. List what's on disk:

```bash
find /tmp/warehouse/db/people -type f
```

**Expected output** (exact filenames will differ — they include random UUIDs):

```
/tmp/warehouse/db/people/metadata/00000-....metadata.json
/tmp/warehouse/db/people/metadata/00001-....metadata.json
/tmp/warehouse/db/people/metadata/snap-....avro
/tmp/warehouse/db/people/metadata/....avro
/tmp/warehouse/db/people/data/00000-....parquet
/tmp/warehouse/db/people/data/00000-....parquet
```

Notice three layers: a `metadata.json` file per schema/snapshot change (the current table state),
Avro manifest and manifest-list files (the index over data files), and Parquet files under `data/`
(the actual rows). You can also ask Iceberg directly instead of walking the filesystem:

```python
spark.sql("SELECT * FROM local.db.people.files").show(truncate=False)
spark.sql("SELECT * FROM local.db.people.snapshots").show(truncate=False)
```

**Expected output:** one row per data file in `.files` (two, from the SQL insert and the DataFrame
append), and one row per snapshot in `.snapshots` (two: the `INSERT INTO` and the `append()`).

# Common Pitfalls

- **Using the v1 `df.write.format("iceberg")` API instead of `writeTo(...)`.** It's still supported
  but not recommended — with a catalog, prefer `writeTo(...).append()`, which resolves the table by
  name and stays consistent with SQL's `INSERT INTO` semantics.
- **Forgetting the namespace.** `CREATE TABLE local.db.people` fails if the `db` namespace doesn't
  exist yet — always `CREATE NAMESPACE IF NOT EXISTS db` first.
- **Expecting row order on read.** Iceberg (like most table formats) does not guarantee row order
  unless you `ORDER BY` — don't assume the DataFrame API returns rows in insertion order.
- **One `INSERT`/`append()` per row in a loop.** Each call creates a new snapshot and at least one
  new small data file. Fine for this tutorial's two examples, but doing this dozens of times in
  production creates the "small file problem" — covered in
  [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md).

# Next Steps

Continue to [3. Schema and Partition Evolution](/tutorials/03-schema-and-partition-evolution.md) to
change this table's shape without rewriting its data.

For the concepts behind the file layout you just inspected, see
[/architecture/table-format-overview.md](/architecture/table-format-overview.md) and
[/architecture/metadata-layer.md](/architecture/metadata-layer.md).

# Citations

[1] [Iceberg Getting Started (Spark) — Writing and Reading](https://iceberg.apache.org/docs/latest/spark-getting-started/)
[2] [Spark DDL — CREATE TABLE](https://iceberg.apache.org/docs/latest/spark-ddl/)
[3] [Spark Writes — Writing with SQL and DataFrames](https://iceberg.apache.org/docs/latest/spark-writes/)
[4] [Spark Queries — Querying with SQL and DataFrames](https://iceberg.apache.org/docs/latest/spark-queries/)
