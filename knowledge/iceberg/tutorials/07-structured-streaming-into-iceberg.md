---
type: Tutorial
title: 7. Structured Streaming into Iceberg
description: Stream from Spark's built-in rate source into an Iceberg table, then read that table back as a second streaming query — no Kafka required.
aliases: [iceberg structured streaming, iceberg writeStream, iceberg readStream, spark rate source iceberg]
tags: [tutorial, pyspark, structured-streaming, intermediate]
timestamp: 2026-07-31T00:00:00Z
difficulty: intermediate
---

# Prerequisites

Complete [1. Environment Setup](/tutorials/01-environment-setup.md) through
[6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md) — this tutorial
directly builds on the small-file problem from tutorial 6, since streaming writes are one of the
most common sources of it.

# What You'll Learn

- How to write a Spark Structured Streaming query into an Iceberg table with `writeStream`, using
  the built-in `rate` source so no external system (Kafka, sockets, etc.) is needed.
- How to read from that same Iceberg table as a streaming source with `readStream`, in a second
  query.
- Why streaming writes make small files worse than batch writes, and what to do about it.

# Steps

## 1. Set up Spark and create the target table

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
spark.sql("DROP TABLE IF EXISTS local.db.ticks PURGE")
spark.sql("""
    CREATE TABLE local.db.ticks (
        tick_id bigint,
        ts      timestamp
    )
    USING iceberg
""")
```

**Expected output:** an empty `ticks` table, ready to receive streaming writes.

## 2. Stream from the `rate` source into the table

The `rate` source generates rows on its own (one column `value: long`, one column
`timestamp: timestamp`) — perfect for a self-contained demo with no external dependencies:

```python
import time

rate_stream = spark.readStream.format("rate").option("rowsPerSecond", 1).load()

ticks_stream = rate_stream.selectExpr("value AS tick_id", "timestamp AS ts")

write_query = (
    ticks_stream.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(processingTime="5 seconds")
    .option("checkpointLocation", "/tmp/warehouse/checkpoints/ticks_write")
    .toTable("local.db.ticks")
)

# Let it run for 20 seconds, producing a handful of micro-batches, then stop.
time.sleep(20)
write_query.stop()
```

**Expected output:** no errors while the query runs. After `stop()`, the streaming query has
committed several micro-batches — each on its own 5-second trigger — as separate snapshots.

## 3. Verify what streaming wrote

```python
spark.sql("SELECT COUNT(*) FROM local.db.ticks").show()
spark.sql("SELECT COUNT(*) AS file_count FROM local.db.ticks.files").show()
```

**Expected output:** roughly 15-20 rows (about 1 row/second for 20 seconds), and a file count close
to the number of micro-batches that committed (roughly 4, at one file per 5-second trigger) — each
micro-batch commit is its own small append, the same pattern you manually simulated in
[6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md).

## 4. Read the same table back as a stream

In a second cell (or a separate script), read from `local.db.ticks` as a streaming source and print
new rows to the console as they arrive. Since the write query above has already stopped, run a
short new batch of writes concurrently with this read, or simply observe that a fresh read starting
now will pick up any snapshot appended after it starts:

```python
read_query = (
    spark.readStream
    .format("iceberg")
    .load("local.db.ticks")
    .writeStream
    .format("console")
    .outputMode("append")
    .trigger(processingTime="5 seconds")
    .option("checkpointLocation", "/tmp/warehouse/checkpoints/ticks_read")
    .start()
)

# Restart the write stream briefly so the reader has new snapshots to pick up.
write_query_2 = (
    ticks_stream.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(processingTime="5 seconds")
    .option("checkpointLocation", "/tmp/warehouse/checkpoints/ticks_write")
    .toTable("local.db.ticks")
)

time.sleep(20)
write_query_2.stop()
read_query.stop()
```

**Expected output:** the console sink prints batches of `tick_id`/`ts` rows as the write query
commits new snapshots — proof that Iceberg tables work as both a streaming sink and a streaming
source. Iceberg's streaming reader only picks up **append** snapshots by default; overwrite and
delete snapshots raise an exception unless you set `streaming-skip-overwrite-snapshots` /
`streaming-skip-delete-snapshots`.

# Common Pitfalls

- **Reusing a checkpoint location across schema or query changes.** Each `checkpointLocation` is
  tied to one specific streaming query definition — reusing it after changing the query's logic (or
  pointing two different queries at the same path, as almost happened in step 4) causes confusing
  state errors. Use a distinct path per query, as done above.
- **Underestimating the small-file impact.** A 1-minute trigger interval on a modest-throughput
  stream can still produce thousands of tiny files a day. The Iceberg project recommends a trigger
  interval of at least 1 minute in production and regular compaction — see
  [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md).
- **Forgetting the table must already exist.** Unlike some sinks, Iceberg's streaming writer does
  not create the target table for you — `CREATE TABLE ... USING iceberg` first, as in step 1.
- **Using `Trigger.Once` for rate limiting.** The deprecated one-shot trigger ignores Iceberg's
  micro-batch size limiting options (`streaming-max-files-per-micro-batch`,
  `streaming-max-rows-per-micro-batch`); use `Trigger.AvailableNow` instead if you want to drain all
  available data in bounded micro-batches.

# Next Steps

You've now covered the full PySpark + Iceberg workflow. If you want the same "create, write, read"
experience without Spark or a JVM at all, continue to
[8. PyIceberg Quickstart (No Spark)](/tutorials/08-pyiceberg-quickstart-no-spark.md).

For streaming-specific maintenance guidance, see
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md)
and [/pyspark/structured-streaming.md](/pyspark/structured-streaming.md).

# Citations

[1] [Spark Structured Streaming — Streaming Reads and Writes](https://iceberg.apache.org/docs/latest/spark-structured-streaming/)
[2] [Spark Structured Streaming — Maintenance for streaming tables](https://iceberg.apache.org/docs/latest/spark-structured-streaming/)
