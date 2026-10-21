---
type: Tutorial
title: 6. Compaction and Maintenance
description: Deliberately create a small-files problem with many tiny appends, then fix it with rewrite_data_files, expire_snapshots, and remove_orphan_files.
aliases: [iceberg rewrite_data_files, iceberg compaction tutorial, iceberg expire_snapshots, iceberg small files problem, iceberg remove_orphan_files]
tags: [tutorial, pyspark, maintenance, compaction, procedures, intermediate]
timestamp: 2026-07-31T00:00:00Z
difficulty: intermediate
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) through
[5. Upsert, MERGE INTO, and CDC](/tutorials/05-upsert-merge-and-cdc.md). This tutorial creates its
own fresh table and deliberately makes it messy before cleaning it up.

# What You'll Learn

- Why lots of small appends (a common pattern from streaming and incremental jobs) create a "small
  file problem" — more metadata, slower query planning, worse file-open overhead.
- How to measure it using the `.files` metadata table.
- How to fix it with `CALL system.rewrite_data_files(...)`, and clean up what compaction leaves
  behind with `expire_snapshots` and `remove_orphan_files`.

# Steps

## 1. Set up Spark and create a table

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
spark.sql("DROP TABLE IF EXISTS local.db.metrics PURGE")
spark.sql("""
    CREATE TABLE local.db.metrics (
        id    bigint,
        name  string,
        value double
    )
    USING iceberg
""")
```

## 2. Deliberately create a small-files problem

Simulate 15 separate tiny writes — the pattern you'd get from 15 small incremental jobs or
streaming micro-batches, each committing on its own:

```python
for i in range(15):
    spark.sql(f"""
        INSERT INTO local.db.metrics VALUES
            ({i}, 'cpu_pct', {40.0 + i})
    """)

print("Wrote 15 single-row batches")
```

**Expected output:** `Wrote 15 single-row batches`. Behind the scenes, this created 15 snapshots and
(at least) 15 tiny Parquet files.

## 3. Count files before compaction

```python
file_count_before = spark.sql("SELECT COUNT(*) AS n FROM local.db.metrics.files").collect()[0]["n"]
print(f"Data files before compaction: {file_count_before}")

spark.sql("""
    SELECT file_path, record_count, file_size_in_bytes
    FROM local.db.metrics.files
""").show(truncate=False)
```

**Expected output:** `Data files before compaction: 15` — one small file (well under a megabyte)
per insert.

## 4. Compact with `rewrite_data_files`

```python
result = spark.sql("CALL local.system.rewrite_data_files('db.metrics')")
result.show(truncate=False)
```

**Expected output:** a result row with columns like `rewritten_data_files_count` (`15`),
`added_data_files_count` (likely `1`, since 15 tiny rows easily fit in one target-size file), and
`rewritten_bytes_count`.

## 5. Count files after compaction

```python
file_count_after = spark.sql("SELECT COUNT(*) AS n FROM local.db.metrics.files").collect()[0]["n"]
print(f"Data files after compaction: {file_count_after}")
```

**Expected output:** `Data files after compaction: 1` (or a small number, depending on target file
size defaults) — the 15 tiny files have been consolidated into far fewer, larger files. The row
count and data are unchanged:

```python
spark.sql("SELECT COUNT(*) FROM local.db.metrics").show()
```

**Expected output:** `15` — same row count as before, just packed more efficiently.

## 6. Expire old snapshots

`rewrite_data_files` didn't delete the old small files yet — they're still referenced by the 15
snapshots that existed before compaction, so they're still needed for time travel. To actually
reclaim disk space, expire the old snapshots:

```python
from datetime import datetime

now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

expire_result = spark.sql(f"""
    CALL local.system.expire_snapshots(
        table => 'db.metrics',
        older_than => TIMESTAMP '{now_str}',
        retain_last => 1
    )
""")
expire_result.show(truncate=False)
```

**Expected output:** a result row showing non-zero `deleted_data_files_count` and
`deleted_manifest_files_count` — the small pre-compaction files are now physically removed, and
only the most recent snapshot (`retain_last => 1`) survives. Note that we explicitly pass
`older_than => TIMESTAMP '{now}'`; the procedure's default is 5 days ago, so calling it with no
arguments immediately after writing would find nothing eligible to expire.

## 7. Clean up orphan files

```python
orphan_result = spark.sql("""
    CALL local.system.remove_orphan_files(table => 'db.metrics', dry_run => true)
""")
orphan_result.show(truncate=False)
```

**Expected output:** in this tutorial, an empty result — there shouldn't be any true orphan files
(files present on disk but not referenced by any table metadata), since every file here came from a
normal Iceberg write. `remove_orphan_files` is a safety net for cleaning up debris left behind by
failed or retried jobs, not part of routine compaction. `dry_run => true` lists candidates without
deleting anything — always start there against a real table.

# Common Pitfalls

- **Expecting `rewrite_data_files` to shrink disk usage immediately.** It doesn't delete the old
  small files — it adds new, larger files and updates the current snapshot to point at them. The
  old files are only removed once their snapshots are expired (step 6).
- **Calling `expire_snapshots` with no arguments right after a demo like this.** The default
  `older_than` is 5 days ago — nothing will be eligible yet. Pass an explicit `older_than` timestamp
  (as done above) if you want to see the effect immediately, but in production, the sensible default
  window exists precisely to protect in-flight time-travel queries.
- **Lowering `remove_orphan_files`'s `older_than` aggressively in production.** The default is 3
  days for a reason: if a write is still in progress when the scan runs, its not-yet-committed files
  can look "orphaned" and get deleted, corrupting the write. Never set this below the time your
  longest-running write job could take.
- **Letting streaming or frequent-batch jobs run indefinitely without compaction.** The pattern in
  step 2 (many tiny single-row commits) is exactly what streaming writes produce continuously —
  see [7. Structured Streaming into Iceberg](/tutorials/07-structured-streaming-into-iceberg.md) for
  why this matters even more there.

# Next Steps

Continue to [7. Structured Streaming into Iceberg](/tutorials/07-structured-streaming-into-iceberg.md),
where the small-file problem shows up naturally rather than being simulated in a loop.

For maintenance strategy beyond a single manual run, see
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md) and
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md).

# Citations

[1] [Spark Procedures — rewrite_data_files](https://iceberg.apache.org/docs/latest/spark-procedures/)
[2] [Spark Procedures — expire_snapshots](https://iceberg.apache.org/docs/latest/spark-procedures/)
[3] [Spark Procedures — remove_orphan_files](https://iceberg.apache.org/docs/latest/spark-procedures/)
[4] [Iceberg Maintenance — recommended and optional maintenance operations](https://iceberg.apache.org/docs/latest/maintenance/)
