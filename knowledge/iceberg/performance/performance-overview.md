---
type: Performance Guide
title: Performance Overview
description: Iceberg's performance design goals — metadata-based scan planning that avoids file listing — and what makes queries fast or slow at a high level.
aliases: [scan planning, metadata filtering, manifest list, iceberg performance design, why is iceberg fast]
tags: [iceberg, performance, scan-planning, metadata, architecture]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/performance/
---

# Retrieval Notes

Read this first for a mental model of *why* Iceberg is fast at scale before
diving into specific tuning topics:
[/performance/partitioning-strategy-for-performance.md](/performance/partitioning-strategy-for-performance.md),
[/performance/sort-order-and-file-layout.md](/performance/sort-order-and-file-layout.md),
[/performance/read-write-performance-tuning.md](/performance/read-write-performance-tuning.md).
For the metadata structures referenced here (manifests, manifest lists),
see [/architecture/](/architecture/). For keeping this metadata index
healthy over time, see
[/maintenance/rewrite-manifests.md](/maintenance/rewrite-manifests.md).

# Summary

- Iceberg is designed for **huge tables** — production tables can hold tens
  of petabytes, and even multi-petabyte tables can be *scan-planned* from a
  single node without a distributed engine.
- The core performance idea: **scan planning uses metadata, not file
  listing**. Instead of listing directories to discover files (slow, and
  inconsistent under concurrent writes), Iceberg reads a hierarchical
  metadata index that already knows every file and its statistics.
- Two levels of metadata make this possible: **manifest lists** (index over
  manifests, with per-manifest partition value ranges) and **manifest
  files** (list of data files, with per-file partition data and column
  stats).
- Planning applies filters in two stages: first prune whole **manifests**
  using partition ranges from the manifest list, then prune individual
  **data files** using per-file column stats (min/max, null counts) from
  the surviving manifests.
- Fast, single-node planning enables lower query latency (no need to run a
  distributed job just to figure out what to scan) and lets any
  stand-alone client read Iceberg tables directly, without going through a
  cluster.
- This stat-based file pruning can yield large wins — cited as up to a 10x
  improvement — when data is well clustered relative to the query
  predicate, which is why layout (partitioning, sort order) is a first-class
  performance lever, not an afterthought.

# Scan Planning: How It Works

"Scan planning" is the process of determining which files a query actually
needs to read.

1. **Manifest-list filtering** — the manifest list for the target snapshot
   stores, per manifest, the range of values for each partition field (plus
   counts of files added/deleted). Iceberg uses the query's predicate on
   partition columns to eliminate manifests whose ranges can't possibly
   match, without opening those manifests at all.
2. **Manifest / data-file filtering** — for the manifests that survive step
   1, Iceberg reads their entries. Each entry carries the file's partition
   values (filtered again) and column-level stats: value counts, null
   counts, and lower/upper bounds. The query predicate is evaluated against
   these bounds to eliminate individual data files that provably cannot
   contain matching rows.

Because both stages work off compact metadata rather than the data files
themselves, this entire process can run on a single node even for tables
with petabytes of underlying data — the "index" (manifest list + manifests)
is orders of magnitude smaller than the data it describes.

# What Makes Queries Fast or Slow

| Fast | Slow |
|---|---|
| Query predicates align with partition columns → whole manifests pruned early | Predicates only on non-partition columns → most/all manifests must be opened |
| Data clustered so column min/max ranges are tight per file → many files pruned by stats | Data scattered so every file's min/max spans the whole domain → stats can't eliminate anything |
| Well-sized files (not too many, not too few) → manifest metadata stays compact | Many small files → manifests bloat, more entries to scan even after pruning |
| Manifests well-organized relative to query pattern | Manifest fragmentation → more manifests survive the first filtering stage than necessary |

This is why the other performance concepts in this bundle — partitioning
choice, sort order/z-order, and manifest health — are really different
levers on the same underlying mechanism: making the metadata-based pruning
in scan planning as effective as possible.

# Citations

[1] [Apache Iceberg — Performance](https://iceberg.apache.org/docs/latest/performance/)
