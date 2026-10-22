---
type: PySpark Guide
title: Structured Streaming Reads and Writes on Iceberg Tables
description: readStream/writeStream options for Iceberg with PySpark Structured Streaming — incremental reads, micro-batch rate limiting, append/complete output modes, fanout writer, and why streaming tables need regular maintenance.
aliases: [iceberg readStream, iceberg writeStream, structured streaming iceberg pyspark, stream-from-timestamp, streaming-max-files-per-micro-batch, fanout-enabled streaming, iceberg checkpointLocation, streaming small files iceberg]
tags: [iceberg, pyspark, spark, structured-streaming, streaming, maintenance]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-structured-streaming
---

# Retrieval Notes

Read this for streaming ingestion into or out of Iceberg tables with
Spark Structured Streaming. For one-shot batch reads/writes see
`/pyspark/reading-data-and-queries.md` and `/pyspark/writing-data.md`. For
the compaction, snapshot-expiry, and manifest-rewrite procedures this file
references as required maintenance, see
`/maintenance/compaction-and-file-sizing.md` and
`/pyspark/spark-procedures.md` (exact `CALL` syntax for
`rewrite_data_files`, `rewrite_manifests`, `expire_snapshots`).

# Summary

- Iceberg only streams from **append** snapshots. `overwrite` snapshots
  raise an exception by default (ignore via
  `streaming-skip-overwrite-snapshots=true`); `delete` snapshots also
  raise by default (ignore via `streaming-skip-delete-snapshots=true`).
- Micro-batch size can be capped with `streaming-max-files-per-micro-batch`
  (hard cap on file count) and/or `streaming-max-rows-per-micro-batch`
  (soft cap on row count — a batch always includes every row of the next
  unprocessed file, even if that exceeds the soft max). Whichever limit
  is hit first wins. These apply to `Trigger.ProcessingTime` (default)
  and `Trigger.AvailableNow`, but are ignored under the deprecated
  `Trigger.Once`.
- Streaming writes support only `append` (append each micro-batch) and
  `complete` (replace table contents each micro-batch) output modes.
  Iceberg does **not** support Spark's experimental continuous processing
  mode (no commit interface).
- Partitioned tables normally require per-task sort-by-partition before
  writing; for streaming, avoid the extra sort/repartition latency by
  enabling the **fanout writer** (`fanout-enabled=true`) instead — but
  don't use it for batch writes, where an explicit sort is cheap.
- **Streaming writes create many small files and many snapshots fast** —
  this is the direct cause of the small-file problem discussed in
  `/maintenance/compaction-and-file-sizing.md`. Iceberg's own docs
  recommend: keep the streaming trigger interval at 1 minute or more,
  regularly run `expire_snapshots` (default retention: 5 days), regularly
  run `rewrite_data_files` to compact small files, and regularly run
  `rewrite_manifests` because streaming's fast-append commits skip
  automatic manifest compaction.

# Streaming Reads

```python
df = (
    spark.readStream
    .format("iceberg")
    .option("stream-from-timestamp", str(stream_start_timestamp))
    .load("database.table_name")
)
```

> Only append snapshots are processed by default. Overwrite/delete
> snapshots raise an exception unless explicitly ignored:
> `.option("streaming-skip-overwrite-snapshots", "true")` /
> `.option("streaming-skip-delete-snapshots", "true")`.

## Limit input rate

```python
# hard cap: 1 file per micro-batch
df = (
    spark.readStream
    .format("iceberg")
    .option("streaming-max-files-per-micro-batch", "1")
    .load("database.table_name")
)

# soft cap: keep reading files until >= 1000 rows accumulated
df = (
    spark.readStream
    .format("iceberg")
    .option("streaming-max-rows-per-micro-batch", "1000")
    .load("database.table_name")
)
```

Setting both applies whichever limit is reached first. Rate limiting also
applies when using `Trigger.AvailableNow` (splits one-time processing of
all available data into several micro-batches for scalability), but is
ignored under the deprecated `Trigger.Once`.

## Asynchronous micro-batch planning

```python
df = (
    spark.readStream
    .format("iceberg")
    .option("async-micro-batch-planning-enabled", "true")
    .load("database.table_name")
)
```

Iceberg processes the current micro-batch while planning the next one in
parallel — improves throughput at the cost of higher memory usage and
increased snapshot-detection latency. Related tuning options
(`streaming-snapshot-polling-interval-ms`, `async-queue-preload-file-limit`,
`async-queue-preload-row-limit`) are listed in
`/pyspark/setup-and-configuration.md`.

# Streaming Writes

```python
(
    data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(processingTime="1 minute")
    .option("checkpointLocation", checkpoint_path)
    .toTable("database.table_name")
)
```

For a directory-based (Hadoop) catalog, use `path` + `.start()` instead of
`toTable(...)`:

```python
(
    data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(processingTime="1 minute")
    .option("path", "hdfs://nn:8020/path/to/table")
    .option("checkpointLocation", checkpoint_path)
    .start()
)
```

Supported output modes:

| Mode | Behavior |
|---|---|
| `append` | Appends each micro-batch's rows to the table |
| `complete` | Replaces the entire table contents with each micro-batch |

The target table must already exist before starting the stream — create
it first with `CREATE TABLE` (see `/pyspark/ddl-create-alter-tables.md`).
Iceberg does not support Spark's experimental continuous-processing mode,
since it has no "commit" interface for Iceberg to hook into.

## Partitioned tables and the fanout writer

Writing to a partitioned table normally requires Spark to sort/cluster
each task's rows by partition before writing (see distribution modes in
`/pyspark/writing-data.md`). For streaming, that extra sort/repartition
adds latency per micro-batch — avoid it with the fanout writer:

```python
(
    data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(processingTime="1 minute")
    .option("fanout-enabled", "true")
    .option("checkpointLocation", checkpoint_path)
    .toTable("database.table_name")
)
```

The fanout writer opens one file per distinct partition value and keeps
all of them open until the write task finishes — memory/file-handle cost
that's usually fine for streaming's small batches, but is **not**
recommended for batch writes, where an explicit sort is cheap and avoids
holding many file handles open at once.

# Maintenance for Streaming Tables

Streaming produces new snapshots (and their metadata) rapidly — this
section is why streaming tables need noticeably more maintenance
attention than batch-written ones.

| Concern | Why it matters | Mitigation |
|---|---|---|
| High commit rate | Each micro-batch commit adds data files, manifests, and a snapshot — more of all three means more to maintain | Keep the streaming trigger interval at **1 minute minimum**; increase if maintenance load is too high |
| Snapshot accumulation | Every batch = a new snapshot retained until expired | Run `expire_snapshots` regularly (default: expires snapshots older than 5 days) — see `/pyspark/spark-procedures.md` |
| Small data files | Streaming batches are typically small, producing many small files and bloating metadata | Run `rewrite_data_files` regularly to compact — see `/maintenance/compaction-and-file-sizing.md` and `/pyspark/spark-procedures.md` |
| Small manifest files | Streaming uses "fast" appends that skip automatic manifest compaction, causing many small manifests | Run `rewrite_manifests` regularly — see `/pyspark/spark-procedures.md` — or, since Iceberg 1.12, set the write option `use-merge-append-for-streaming=true` so manifests are merged on commit |

# Citations

[1] [Spark Structured Streaming](https://iceberg.apache.org/docs/latest/spark-structured-streaming)
