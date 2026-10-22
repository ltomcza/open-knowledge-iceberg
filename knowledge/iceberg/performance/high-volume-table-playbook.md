---
type: Playbook
title: High-Volume Table Playbook (100M–1B+ rows/day)
description: End-to-end design and tuning profile for Iceberg tables ingesting hundreds of millions of rows per day with frequent updates — partition/bucket design, sort order, file and Parquet sizing, bloom filters, metrics, manifest and planning settings, object-storage layout, and a daily operating schedule.
aliases: [400 million rows per day, billions of rows iceberg, high throughput iceberg, large iceberg table design, iceberg at scale, iceberg production profile, performance critical iceberg]
tags: [iceberg, performance, playbook, design, parquet, partitioning, maintenance, spark, synthesis]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/configuration/
---

# Retrieval Notes

Read this when designing or re-tuning a single very large, performance-
critical Iceberg table, for example one that ingests 400M+ rows/day and
also receives bulk updates. It ties together the specialized concepts:
[partitioning](/performance/partitioning-strategy-for-performance.md),
[sort order](/performance/sort-order-and-file-layout.md),
[Spark read/write knobs](/performance/read-write-performance-tuning.md),
[MERGE tuning](/performance/large-scale-merge-and-update-tuning.md),
[SPJ](/performance/storage-partitioned-joins.md), and the
[post-update runbook](/maintenance/post-update-maintenance-runbook.md).

This is **synthesis**: official property semantics combined with
practitioner sources (Ancestry/AWS, Cloudera, Dremio, AWS prescriptive
guidance, DataOS). Benchmark everything on your own data.

# Summary

- **Back-of-envelope numbers first.** 400M rows/day at about 100–200 bytes
  per row compressed is about 40–80 GB/day. At a 512 MB target that is
  roughly 80–160 well-sized files per day, and about 30–60k data files per
  year. Iceberg handles that easily *if* files stay near the target size.
  Without compaction, a single micro-batched or `none`-distributed day can
  produce tens of thousands of files.
- **Partition by time at the granularity you query and maintain**
  (`days(ts)` is typical at this volume). Add **`bucket(N, key)`** only
  if you merge or join on that key (it enables SPJ) and each bucket per day
  still holds roughly ≥ 100–512 MB.
- **Sort or cluster within partitions** on the most selective filter
  column(s), so min/max stats prune files. Use `truncate` on high-
  cardinality IDs to make sorting cheap (Ancestry's `truncate(100_000_000,
  hintId)`).
- **Files: 256–512 MB. Row groups: about 128 MB. Compression: zstd.**
  Add Parquet **bloom filters** only on high-cardinality equality-lookup
  columns that sorting can't cluster.
- **Metadata:** make sure filter columns have metrics (the first 100
  columns get them by default). Keep manifests clustered by running
  `rewrite_manifests`. Use distributed planning for selective scans
  without partition predicates.
- **Operate on a daily cadence:** ingest, merge (MOR), scoped compaction,
  delete-file cleanup, manifest rewrite, snapshot expiry, stats.

# 1. Table Layout

```sql
CREATE TABLE prod.db.events (
  event_id    BIGINT,
  account_id  BIGINT,
  event_type  STRING,
  ts          TIMESTAMP,
  payload     STRING
)
USING iceberg
PARTITIONED BY (days(ts), bucket(64, account_id))   -- bucket only if you MERGE/join on account_id
TBLPROPERTIES (
  'format-version'                    = '2',        -- '3' for deletion vectors, once every reader supports v3
  'write.target-file-size-bytes'      = '536870912',
  'write.parquet.row-group-size-bytes'= '134217728',
  'write.parquet.compression-codec'   = 'zstd',
  'write.distribution-mode'           = 'hash',
  'write.merge.mode'                  = 'merge-on-read',
  'write.update.mode'                 = 'merge-on-read',
  'write.delete.mode'                 = 'merge-on-read',
  'write.merge.distribution-mode'     = 'hash',
  'write.metadata.delete-after-commit.enabled' = 'true',
  'write.metadata.previous-versions-max'       = '50',
  'history.expire.max-snapshot-age-ms'         = '259200000'   -- 3 days, adjust to your time-travel needs
);

ALTER TABLE prod.db.events WRITE ORDERED BY event_type, event_id;
```

Bucket sizing check: daily volume ÷ bucket count ≈ per-bucket-per-day
size. At 60 GB/day and 64 buckets that is about 940 MB, which is roughly 2
files of 512 MB each. That's good. Using 1024 buckets would give about
60 MB fragments, which is too small. See
[/performance/partitioning-strategy-for-performance.md](/performance/partitioning-strategy-for-performance.md).

Avoid partitioning on high-cardinality columns directly. Use
`bucket`/`truncate` transforms instead. Partition evolution lets you
change the layout later without rewriting history.

# 2. File, Row-Group, and Encoding Settings

| Property | Default | Recommendation at this scale | Why |
|---|---|---|---|
| `write.target-file-size-bytes` | 512 MB | 256–512 MB | Fewer files and cheaper planning. Very large files reduce pruning and parallelism |
| `write.parquet.row-group-size-bytes` | 128 MB | 128 MB (lower it for very selective point lookups) | Row group is the unit of stats and bloom-filter skipping |
| `write.parquet.row-group-size-track-uncompressed` | false | Consider `true` with zstd | Enforces row-group size more accurately when the codec compresses heavily |
| `write.parquet.compression-codec` | zstd | zstd (tune `compression-level`) | Best ratio/speed for analytics |
| `write.parquet.bloom-filter-enabled.column.<col>` | unset | `true` on 1–3 high-NDV equality-lookup columns (IDs, UUIDs) | Skips row groups where min/max can't help |
| `write.parquet.bloom-filter-ndv.column.<col>` / `bloom-filter-fpp` / `bloom-filter-adaptive-enabled` | — | Set NDV per row group or use adaptive sizing. FPP 0.01 | Right-sized filters, no waste of the 1 MB max |
| `write.metadata.metrics.default` | `truncate(16)` | Keep it. Set `none`/`counts` on wide payload columns you never filter | Smaller manifests |
| `write.metadata.metrics.max-inferred-column-defaults` | 100 | Raise it, or reorder columns, if filter columns fall past column 100 | Columns without metrics **cannot** be pruned |

In Spark, a file can't be larger than the task that writes it, and on disk
it is much smaller than the task's in-memory size. Size tasks through AQE:
`spark.sql.adaptive.advisoryPartitionSizeInBytes` (or
`spark.sql.iceberg.advisory-partition-size`) set **above** the target file
size. See [/performance/read-write-performance-tuning.md](/performance/read-write-performance-tuning.md).

# 3. Ingest Pattern (Appends)

- Prefer **fewer, larger commits**: one or a few per batch, not one per
  micro-batch per minute. Each commit adds a snapshot, a manifest list, and
  usually a manifest.
- Keep `commit.manifest-merge.enabled=true` (the default) so appends merge
  manifests once `commit.manifest.min-count-to-merge` (100) is reached.
  Streaming appends can opt in with the `use-merge-append-for-streaming`
  write option.
- With **concurrent writers** (ingest plus merge plus compaction), raise
  `commit.retry.num-retries` (default 4) and give non-overlapping partition
  ranges to different jobs where possible.
- On S3, `write.object-storage.enabled=true` hashes file paths across
  prefixes so very high write rates don't hit per-prefix throttling.

# 4. Updates

Use MOR for the update/merge, follow it with scoped compaction, and
design the merge for pushdown and SPJ. All the details are in
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md).

# 5. Read Side

| Knob | Setting | Use |
|---|---|---|
| `read.data-planning-mode` / `spark.sql.iceberg.data-planning-mode` | `auto` (default), `local`, `distributed` | `distributed` plans on executors. The Iceberg PR benchmark planned a min/max-only filter on a 20M-file table in 3 s instead of 30 s. For full scans, raise `spark.driver.maxResultSize`, enable Kryo, and add driver cores |
| `read.delete-planning-mode` | `auto` | Same idea for delete manifests on delete-heavy MOR tables |
| `read.split.adaptive-size.enabled` | `true` | Lets Iceberg size splits to the scan and the cluster's parallelism |
| `spark.sql.iceberg.executor-cache.*` | enabled, 128 MB total | Raise `max-total-size` for MOR tables whose delete files are reused across tasks |
| `spark.sql.iceberg.aggregate-push-down.enabled` | `true` | `COUNT/MIN/MAX` answered from metadata when no deletes are present (since 1.11, MIN/MAX push-down is disabled for string and binary columns) |
| `spark.sql.iceberg.report-column-stats` + CBO | `true` | Uses Puffin NDV stats from `compute_table_stats` to choose joins |

Queries with a partition predicate plan in about a second even with 20M+
files, provided manifests are clustered (`rewrite_manifests`). Most slow
planning traces back to fragmented manifests or to filters on columns
without metrics.

# 6. Daily Operating Schedule (Example)

| When | Job | Scope |
|---|---|---|
| Continuous / hourly | Ingest appends (few large commits) | Current day |
| After each update batch | `MERGE` (MOR) | Touched days only |
| Right after the merge | `rewrite_data_files` with delete thresholds, `partial-progress` | Touched days, excluding the partition currently being written |
| Right after compaction | `rewrite_position_delete_files`, `rewrite_manifests` | Same scope / whole table |
| Daily (off-peak) | `rewrite_data_files` `strategy => 'sort'` on yesterday's (now cold) partition | Yesterday |
| Daily | `expire_snapshots` (`max_concurrent_deletes`, `stream_results`), `compute_table_stats` | Table |
| Weekly | `remove_orphan_files` (≥ 3-day safety window) | Table |

Step-by-step commands are in
[/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).

# 7. What to Monitor

- Files per partition and average file size (`data_files`).
- Delete files and deleted rows per partition (`delete_files`,
  `partitions.position_delete_record_count`).
- Manifest count and size (`manifests`).
- Snapshot count and the `summary` of each commit (`snapshots`). Watch for
  unexpectedly large `removed-files-size` on merges.
- Scan-planning duration and `skippedDataFiles` via a `MetricsReporter`.
  See [/performance/metrics-and-monitoring.md](/performance/metrics-and-monitoring.md).

Alert when delete-file counts or small-file counts per partition cross a
threshold, and trigger compaction from those events instead of only on a
fixed schedule.

# Citations

[1] [Apache Iceberg — Configuration (write, read, table behavior properties)](https://iceberg.apache.org/docs/latest/configuration/)
[2] [Apache Iceberg — Spark Configuration (SQL options)](https://iceberg.apache.org/docs/latest/spark-configuration/)
[3] [Apache Iceberg — Spark Writes: controlling file sizes](https://iceberg.apache.org/docs/latest/spark-writes/)
[4] [AWS Big Data Blog — How Ancestry optimizes a 100-billion-row Iceberg table (2025)](https://aws.amazon.com/blogs/big-data/how-ancestry-optimizes-a-100-billion-row-iceberg-table/)
[5] [Cloudera — Optimization Strategies for Iceberg Tables (2024)](https://www.cloudera.com/blog/technical/optimization-strategies-for-iceberg-tables.html)
[6] [AWS Prescriptive Guidance — Iceberg compaction best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/apache-iceberg-on-aws/best-practices-compaction.html)
[7] [DataOS — Tuning large Lakehouse (Iceberg) loads](https://v2.dataos.info/references/resources/nilus/pipeline-optimization/optimize-sink-datasets/optimize-lakehouse-iceberg-loads)
[8] [apache/iceberg PR #8123 — Spark distributed planning](https://github.com/apache/iceberg/pull/8123)
[9] [Iceberg Javadoc — SparkDistributedDataScan (performance tips)](https://iceberg.apache.org/javadoc/latest/org/apache/iceberg/SparkDistributedDataScan.html)
