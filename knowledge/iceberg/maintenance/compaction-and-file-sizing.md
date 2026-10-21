---
type: Maintenance Guide
title: Compaction and File Sizing
description: Why small files hurt Iceberg performance and how to compact them with rewrite_data_files (bin-pack, sort, z-order strategies).
aliases: [compaction, rewrite_data_files, file compaction, bin-packing, small files problem, target-file-size-bytes]
tags: [iceberg, maintenance, compaction, performance, spark]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/maintenance/
---

# Retrieval Notes

Read this when diagnosing "too many small files" symptoms (slow scan
planning, high file-open overhead) or planning a compaction schedule. For
the exact `CALL` syntax and every option, see
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) (procedure:
`rewrite_data_files`). For choosing sort vs z-order specifically, see
[/performance/sort-order-and-file-layout.md](/performance/sort-order-and-file-layout.md).
For overall scheduling and ordering relative to other maintenance jobs, see
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md).

# Summary

- Iceberg tracks every data file individually in manifests; more files means
  more manifest metadata to read and higher per-file open cost at query
  time, even if total data volume is unchanged.
- Small files are typically produced by low-latency/streaming writers,
  frequent small batch jobs, or highly partitioned tables where each write
  touches many partitions.
- `rewrite_data_files` (the compaction action/procedure) combines small
  files into larger ones and can also split oversized files, targeting
  `target-file-size-bytes` (defaults to the table's `write.target-file-size-bytes`,
  512 MB).
- Three strategies: **bin-pack** (default — combine/split files, no
  reordering of rows), **sort** (bin-pack plus a global sort by a given
  order), **z-order** (bin-pack plus a space-filling-curve sort across
  multiple columns for multi-predicate pruning).
- Compaction can run incrementally with `partial-progress.enabled=true` so
  large rewrites commit in chunks instead of one giant transaction.
- Run compaction regularly and proactively — it is the single highest-leverage
  maintenance operation for query performance on actively written tables.

# Why Small Files Hurt Performance

- **Metadata bloat** — every data file needs an entry (path, partition
  values, column stats) in a manifest. More files → bigger manifests →
  slower scan planning, since Iceberg has to read more manifest data to
  build a scan plan.
- **File-open cost** — opening a file (especially on object storage like S3)
  has a fixed latency cost independent of how much data it contains. Many
  tiny files multiply this fixed cost across a query.
- **Poor compression/encoding efficiency** — small files don't amortize
  columnar format overhead (footers, dictionaries, row groups) as well as
  larger files.

Typical causes: streaming ingestion (each micro-batch commits its own small
files), over-partitioned tables (each write fans out across many partitions,
producing one small file per partition per commit), and low-volume batch
jobs writing on a tight schedule.

# The `rewrite_data_files` Operation

Conceptually, compaction selects groups of files (by partition and size
heuristics), rewrites each group into fewer, appropriately-sized files, and
commits the replacement as a new snapshot — the old files become
unreferenced (and are later cleaned up by
[expire-snapshots](/maintenance/expire-snapshots.md) /
[remove-orphan-files](/maintenance/remove-orphan-files.md)).

Selection heuristics (defaults) that decide which files are rewritten:

| Option | Default | Effect |
|---|---|---|
| `target-file-size-bytes` | 512 MB (table's `write.target-file-size-bytes`) | Target size for output files |
| `min-file-size-bytes` | 75% of target | Files below this are candidates for rewrite |
| `max-file-size-bytes` | 180% of target | Files above this are candidates for rewrite (too large) |
| `min-input-files` | 5 | A partition/group with this many files or more is rewritten even if individually "big enough" |
| `rewrite-all` | false | Force-rewrite everything, ignoring size heuristics |
| `delete-file-threshold` / `delete-ratio-threshold` | unlimited / 0.3 | Also rewrite data files with many/most rows shadowed by delete files (merge-on-read cleanup) |
| `max-concurrent-file-group-rewrites` | 5 | Parallel file groups; raise substantially for tables with many partitions (Ancestry: 100) |
| `max-file-group-size-bytes` | 100 GB | Upper bound per group; lower to avoid OOM, raise to partition size for a full-partition sort |
| `remove-dangling-deletes` | false | Extra commit dropping delete files that no longer apply to live data |
| `cache-delete-files` | false | Executor-cache delete files shared by many data files |
| `rewrite-job-order` | none | `bytes-desc`/`files-desc` etc. to prioritize the worst groups |

Minimal example (full syntax lives in
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md)):

```sql
CALL catalog_name.system.rewrite_data_files('db.sample');
```

# Strategies

| Strategy | What it does | Use when |
|---|---|---|
| `binpack` (default) | Combines small files and splits oversized ones into `target-file-size-bytes` chunks; does not reorder rows | General-purpose, cheapest, run frequently |
| `sort` | Bin-packs, but also globally sorts data by a single-column or multi-column sort order before writing | Queries filter/range-scan on a known leading column (improves min/max stat pruning) |
| `sort` with `zorder(...)` | Bin-packs, then interleaves multiple columns via a z-order curve so files cluster well on *any* of several filter columns | Queries filter on different combinations of 2+ columns, no single dominant predicate column |

```sql
-- sort strategy
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample',
  strategy => 'sort',
  sort_order => 'id DESC NULLS LAST,name ASC NULLS FIRST');

-- z-order strategy
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample',
  strategy => 'sort',
  sort_order => 'zorder(c1,c2)');
```

See
[/performance/sort-order-and-file-layout.md](/performance/sort-order-and-file-layout.md)
for the deeper tradeoff discussion between sort and z-order, and how this
interacts with min/max-based file pruning.

# When and How Often to Run It

- **Streaming/frequent-commit tables**: run compaction often (e.g. hourly
  or after N commits) — these tables generate the most small files.
- **Batch/daily-load tables**: daily or after each load job is usually
  sufficient.
- **Large one-off rewrites**: use `partial-progress.enabled=true` with
  `partial-progress.max-commits` so a big backlog compaction commits
  incrementally rather than as one long-running transaction that could
  fail late and lose all progress.
- Use the `where` predicate to scope compaction to recently-written
  partitions instead of rewriting the whole table every run — much
  cheaper on large tables.
- Inspect the `files` metadata table (`SELECT * FROM db.sample.files`) to
  see current file size distribution and decide whether/where compaction
  is needed before running it blindly.

# After Large Row-Level Updates

On merge-on-read tables, compaction is also how delete files get folded
back into data files — but only if the delete thresholds are set
(`delete-file-threshold` is effectively disabled by default). For the full
post-update sequence (diagnosis queries, delete-aware compaction,
`rewrite_position_delete_files`, manifests, expiry at scale) see
[/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).

# Citations

[1] [Apache Iceberg — Maintenance](https://iceberg.apache.org/docs/latest/maintenance/)
[2] [Apache Iceberg — Spark Procedures: rewrite_data_files](https://iceberg.apache.org/docs/latest/spark-procedures/)
