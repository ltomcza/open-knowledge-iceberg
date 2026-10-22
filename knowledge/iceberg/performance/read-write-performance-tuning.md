---
type: Performance Guide
title: Read/Write Performance Tuning (Spark)
description: Spark-side tuning knobs for Iceberg — vectorized reads, split/advisory partition sizing, fanout writers, worker parallelism, and shuffle-partitions interplay.
aliases: [spark tuning, vectorized reads, split-size, advisory-partition-size, fanout writer, spark.sql.shuffle.partitions, iceberg spark performance]
tags: [iceberg, performance, spark, tuning, reads, writes]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-configuration/
---

# Retrieval Notes

Read this for concrete Spark configuration knobs once you understand *why*
they matter from
[/performance/performance-overview.md](/performance/performance-overview.md).
For catalog-level Spark configuration (not read/write tuning), see
[/pyspark/](/pyspark/). For the write-side tuning that belongs to
compaction rather than ordinary writes, see
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md).

# Summary

- **Vectorized reads** (Parquet on by default, ORC off by default) batch-decode
  columnar data instead of row-by-row, and are controlled globally
  (`spark.sql.iceberg.vectorization.enabled`), per-read
  (`vectorization-enabled` DataFrameReader option), or per-table
  (`read.parquet.vectorization.enabled` / `read.orc.vectorization.enabled`).
- **Split sizing** controls how Iceberg groups file regions into Spark
  tasks for scan planning — bigger splits mean fewer, larger tasks;
  `read.split.target-size` (128 MB default) and `read.split.open-file-cost`
  (4 MB default, a per-file penalty used when combining splits) are the
  key knobs.
- **`spark.sql.iceberg.advisory-partition-size`** is the write-side
  equivalent under Adaptive Query Execution (AQE) — it advises Spark on
  output file/partition sizing when AQE is enabled.
- **Fanout writers** (`write.spark.fanout.enabled` / `fanout-enabled`
  write option) let Spark write to many partitions from unsorted input
  without requiring a prior sort/shuffle-by-partition — at the cost of
  keeping more open file writers (more executor memory) simultaneously.
- **`spark.sql.shuffle.partitions`** interacts with Iceberg's own
  `distribution-mode` — Iceberg can hash/range-distribute rows by
  partition key before writing, and the shuffle partition count then
  determines how many output tasks (and therefore how many output files
  per partition) are produced.
- Configuration precedence, high to low: DataFrame `.option(...)` > Spark
  session config > Iceberg table properties > built-in default.

# Vectorized Reads

Vectorized decoding processes a batch of rows at once (columnar
batch-decode) instead of row-at-a-time, which is significantly faster for
scan-heavy workloads on Parquet.

| Setting | Level | Default | Notes |
|---|---|---|---|
| `spark.sql.iceberg.vectorization.enabled` | Spark session | table default | Global override |
| `vectorization-enabled` | DataFrameReader option | table default | Per-read override |
| `read.parquet.vectorization.enabled` | table property | `true` | Parquet vectorization |
| `read.orc.vectorization.enabled` | table property | `false` | ORC vectorization (off by default) |
| `read.parquet.vectorization.batch-size` / `read.orc.vectorization.batch-size` | table property | 5000 | Rows per vectorized batch |

```scala
// disabling vectorization at the session level
val spark = SparkSession.builder()
  .config("spark.sql.iceberg.vectorization.enabled", "false")
  .getOrCreate()
```

# Split Size and Scan Planning

Iceberg groups file byte-ranges into "splits," which become Spark task
input units during scan planning.

| Setting | Level | Default | Effect |
|---|---|---|---|
| `read.split.target-size` | table property (override: `split-size` read option) | 134217728 (128 MB) | Target size for combined input splits |
| `read.split.metadata-target-size` | table property | 33554432 (32 MB) | Target size for combined metadata splits |
| `read.split.planning-lookback` | table property (override: `lookback` read option) | 10 | Number of bins considered when combining splits |
| `read.split.open-file-cost` | table property (override: `file-open-cost` read option) | 4194304 (4 MB) | Minimum weight assigned per file when combining splits, modeling the fixed cost of opening a file |

Larger `target-size` → fewer, bigger Spark tasks (less scheduling overhead,
but less parallelism and potentially worse skew handling). `open-file-cost`
matters most when a partition/split candidate contains many small files —
it prevents Spark from combining an unreasonable number of tiny files into
one split purely because their total bytes are small, by charging each file
a minimum notional weight.

# Advisory Partition Size (Write-Side, AQE)

`spark.sql.iceberg.advisory-partition-size` advises Spark's Adaptive Query
Execution on target output partition size when writing to an Iceberg
table, influencing output file sizing similarly to
`target-file-size-bytes` but working through AQE's own partition-coalescing
logic rather than Iceberg's writer directly.

# Fanout Writers for Unsorted Input

By default, Spark's Iceberg writer expects data to be clustered by
partition (typically via `write.distribution-mode`) so it can write to one
partition's files at a time. If input isn't sorted/clustered, this either
requires a shuffle to sort it first or, if using the **fanout writer**,
allows opening multiple output files simultaneously across whatever
partitions appear in the input, avoiding the need to pre-sort.

| Setting | Level | Default | Tradeoff |
|---|---|---|---|
| `write.spark.fanout.enabled` | table property | `false` | Off by default |
| `fanout-enabled` | write option | overrides table property | Per-write override |

Enabling fanout trades **executor memory** (many concurrently open file
writers, one per partition touched) for avoiding an upstream sort/shuffle
step. Useful when input partitioning is unpredictable or when the cost of
a pre-write shuffle outweighs the memory cost of fanout on your cluster.

# Worker Parallelism and `spark.sql.shuffle.partitions`

Iceberg's `write.distribution-mode` (table property) or `distribution-mode`
(write option) controls whether/how rows are redistributed before writing:
`none` (no shuffle), `hash` (hash-distribute by partition key), or `range`
(range-distribute by partition key or table sort key). When a shuffle is
used (`hash`/`range`), **`spark.sql.shuffle.partitions`** determines how
many shuffle output partitions — and therefore how many concurrent writer
tasks, and roughly how many output files per table partition — the write
produces.

Practical interplay:

- Too few shuffle partitions relative to the number of table partitions
  being written to → each task may still write to many partitions (fanout
  needed) or files end up larger/fewer than desired.
- Too many shuffle partitions relative to data volume → many small output
  files per partition, undermining the target file size and creating work
  for later [compaction](/maintenance/compaction-and-file-sizing.md).
- A reasonable approach: size `spark.sql.shuffle.partitions` (or rely on
  AQE with `advisory-partition-size`) so that `total write volume /
  shuffle partitions ≈ target-file-size-bytes`, rather than leaving it at a
  generic cluster-wide default tuned for shuffle-heavy joins.

# Planning Mode and Executor Cache (Large Tables)

| Setting | Default | Effect |
|---|---|---|
| `read.data-planning-mode` / `spark.sql.iceberg.data-planning-mode` | `auto` | `local` (driver) or `distributed` (executors filter manifests) — distributed helps selective min/max filters without partition predicates on tables with millions of files |
| `read.delete-planning-mode` / `spark.sql.iceberg.delete-planning-mode` | `auto` | Same, for delete manifests |
| `read.split.adaptive-size.enabled` | `true` | Adapt split size to scan size and parallelism when no explicit split size is set |
| `spark.sql.iceberg.executor-cache.enabled` | `true` | Caches delete files on executors (64 MB/entry, 128 MB total by default) |

For MERGE/UPDATE-specific tuning see
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md);
for a complete high-volume profile see
[/performance/high-volume-table-playbook.md](/performance/high-volume-table-playbook.md).

# Quick Reference: Read/Write Options

```python
# read: override split sizing for one query
spark.read.option("split-size", "268435456").table("catalog.db.table")
```

```python
# write: override target file size and enable fanout for one write
(df.writeTo("catalog.db.table")
  .option("target-file-size-bytes", "268435456")
  .option("fanout-enabled", "true")
  .append())
```

Full option tables (all read/write options, precedence rules) are on the
source page; this file summarizes the ones with direct performance impact.

# Citations

[1] [Apache Iceberg — Spark Configuration](https://iceberg.apache.org/docs/latest/spark-configuration/)
[2] [Apache Iceberg — Configuration: read/write table properties](https://iceberg.apache.org/docs/latest/configuration/#table-properties)
[3] [Apache Iceberg — Performance](https://iceberg.apache.org/docs/latest/performance/)
