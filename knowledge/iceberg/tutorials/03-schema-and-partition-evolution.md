---
type: Tutorial
title: 3. Schema and Partition Evolution
description: Add and rename a column, then change a populated table's partition spec and prove old data files are untouched while new writes follow the new layout.
aliases: [iceberg add column, iceberg rename column, iceberg add partition field, iceberg partition evolution tutorial]
tags: [tutorial, pyspark, schema-evolution, partitioning, intermediate]
timestamp: 2026-07-31T00:00:00Z
difficulty: intermediate
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) and
[2. Your First Table: Create, Insert, Read](/tutorials/02-first-table-crud.md) first. This tutorial
creates its own fresh table, so you don't need to have kept the `people` table from tutorial 2
around — but the pattern is the same one you just learned.

# What You'll Learn

- How to add and rename columns on a live table with `ALTER TABLE ... ADD COLUMNS` / `RENAME COLUMN`.
- How to change a table's **partition spec** after it already has data, with `ADD PARTITION FIELD`.
- Why this is a metadata-only operation — existing data files keep their old layout, and only new
  writes follow the new spec (Iceberg's "hidden partitioning" model).

# Steps

## 1. Set up Spark and create a starting table

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
spark.sql("DROP TABLE IF EXISTS local.db.people PURGE")
spark.sql("""
    CREATE TABLE local.db.people (
        id    bigint,
        name  string,
        email string
    )
    USING iceberg
""")

spark.sql("""
    INSERT INTO local.db.people VALUES
        (1, 'Ada Lovelace', 'ada@example.com'),
        (2, 'Grace Hopper', 'grace@example.com')
""")
```

**Expected output:** no errors; two rows inserted into an unpartitioned table.

## 2. Add a column

```python
spark.sql("""
    ALTER TABLE local.db.people
    ADD COLUMNS (signup_date date COMMENT 'date the person signed up')
""")

spark.sql("DESCRIBE TABLE local.db.people").show(truncate=False)
```

**Expected output:**

```
+-----------+---------+--------------------------+
|col_name   |data_type|comment                   |
+-----------+---------+--------------------------+
|id         |bigint   |null                      |
|name       |string   |null                      |
|email      |string   |null                      |
|signup_date|date     |date the person signed up |
+-----------+---------+--------------------------+
```

The two existing rows now report `signup_date = NULL` — adding a column never rewrites existing
data files; it's purely a metadata change.

## 3. Rename a column

```python
spark.sql("ALTER TABLE local.db.people RENAME COLUMN email TO email_address")

spark.sql("SELECT * FROM local.db.people ORDER BY id").show()
```

**Expected output:**

```
+---+-------------+------------------+-----------+
| id|         name|     email_address|signup_date|
+---+-------------+------------------+-----------+
|  1| Ada Lovelace|   ada@example.com|       null|
|  2| Grace Hopper| grace@example.com|       null|
+---+-------------+------------------+-----------+
```

Iceberg tracks columns by ID internally, not by name, so renaming is also a pure metadata change —
no data files are touched or rewritten.

## 4. Change the partition spec on the already-populated table

The table is unpartitioned so far. Add a partition field now, with data already in it:

```python
spark.sql("ALTER TABLE local.db.people ADD PARTITION FIELD bucket(4, id)")
```

**Expected output:** no errors. This requires Iceberg's SQL extensions (configured in step 1) —
`ADD PARTITION FIELD` is not part of standard Spark SQL.

## 5. Insert more data and observe the new layout

```python
spark.sql("""
    INSERT INTO local.db.people VALUES
        (3, 'Katherine Johnson', 'katherine@example.com', DATE '2026-01-15'),
        (4, 'Margaret Hamilton', 'margaret@example.com', DATE '2026-02-20')
""")
```

Now inspect the `partitions` metadata table:

```python
spark.sql("SELECT * FROM local.db.people.partitions").show(truncate=False)
```

**Expected output (partition values will vary by hash, but the shape matches):**

```
+---------+-------+------------+----------+...
|partition|spec_id|record_count|file_count|...
+---------+-------+------------+----------+...
|{null}   |0      |2           |1         |...
|{1}      |1      |1           |1         |...
|{3}      |1      |1           |1         |...
+---------+-------+------------+----------+...
```

The two rows from step 1 (written under `spec_id=0`, the original unpartitioned spec) show a `null`
partition value — they were never rewritten. The two new rows from this step were written under
`spec_id=1` (the new `bucket(4, id)` spec) and land in real buckets. You can confirm the same story
from `.files`:

```python
spark.sql("SELECT file_path, spec_id, partition FROM local.db.people.files").show(truncate=False)
```

**Expected output:** the two original files show `spec_id = 0`, the new file(s) show `spec_id = 1`
with a populated bucket value — proof that adding a partition field never touches existing data.

# Common Pitfalls

- **Expecting old files to be rewritten into the new partition layout.** They aren't, by design —
  `ADD PARTITION FIELD` (and `DROP PARTITION FIELD`) are metadata-only operations. If you need old
  data physically reorganized, run compaction afterward (see
  [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md)) with
  `output-spec-id` set to the new spec.
- **Forgetting `spark.sql.extensions`.** Without it, `ADD PARTITION FIELD` and similar Iceberg SQL
  extensions simply won't parse — you'll get a syntax error that looks unrelated to the missing
  config.
- **Assuming dynamic `INSERT OVERWRITE` behaves the same before and after a partition change.**
  It doesn't — changing partitioning changes which rows a dynamic overwrite will replace. Prefer
  `MERGE INTO` (see [5. Upsert, MERGE INTO, and CDC](/tutorials/05-upsert-merge-and-cdc.md)) if this
  matters to you.
- **Reordering columns with a Hive catalog.** Not relevant to this tutorial's local Hadoop catalog,
  but worth knowing: a Hive Metastore-backed catalog validates schema changes positionally and can
  reject some `ADD COLUMN ... FIRST/AFTER` or reordering operations that work fine here.

# Next Steps

Continue to [4. Time Travel and Rollback](/tutorials/04-time-travel-and-rollback.md) to explore the
snapshot history this table has already started accumulating.

For the concepts behind what you just did, see
[/architecture/schema-evolution.md](/architecture/schema-evolution.md) and
[/architecture/partitioning-and-hidden-partitioning.md](/architecture/partitioning-and-hidden-partitioning.md).

# Citations

[1] [Spark DDL — ALTER TABLE (columns, and the ALTER TABLE SQL extensions for partitioning)](https://iceberg.apache.org/docs/latest/spark-ddl/)
[2] [Spark Configuration — SQL Extensions](https://iceberg.apache.org/docs/latest/spark-configuration/)
