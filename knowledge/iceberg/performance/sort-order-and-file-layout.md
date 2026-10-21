---
type: Performance Guide
title: Sort Order and File Layout
description: How table sort order improves min/max stat-based file pruning, z-order/Hilbert clustering for multi-column filters, and when to choose sort vs z-order during compaction.
aliases: [sort order, z-order, zorder, hilbert clustering, file layout, min-max pruning, data clustering]
tags: [iceberg, performance, sort-order, z-order, compaction, file-pruning]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/performance/
---

# Retrieval Notes

Read this when a query filters on non-partition columns and you want file
pruning to help anyway, or when deciding what strategy to pass to
compaction. For the mechanics of stat-based pruning during scan planning,
see [/performance/performance-overview.md](/performance/performance-overview.md).
For the exact `CALL rewrite_data_files(...)` syntax with `strategy` and
`sort_order`, see [/pyspark/spark-procedures.md](/pyspark/spark-procedures.md);
this file focuses on *when/why* to choose each option, with the strategy
mechanics summarized briefly in
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md).

# Summary

- Iceberg's data-file pruning during scan planning relies on per-file
  column stats — min/max bounds, null counts — stored in manifests. Pruning
  only works well if those bounds are *tight*, i.e. each file's values are
  clustered rather than spread across the whole domain.
- A **table sort order** controls how data is ordered when written/rewritten,
  which is what makes column bounds tight for the sorted column(s) — a
  file sorted by `id` has a narrow `[min(id), max(id)]` range instead of
  spanning the table's entire id space.
- Sort order gives strong pruning for the **leading sort column** (and
  progressively weaker benefit for later columns, same as a composite
  database index) — it optimizes well for one dominant filter column or
  a fixed filter-column order.
- **Z-order** (a space-filling curve, interleaving bits/bytes of multiple
  columns) sacrifices some single-column pruning strength to give
  *balanced* pruning benefit across several columns simultaneously,
  regardless of which of them a given query filters on.
- Choose **sort** when queries consistently filter/range-scan on one
  column (or a known, stable multi-column order). Choose **z-order** when
  queries filter on varying combinations of 2+ columns and no single
  column dominates.
- Both are applied via the `rewrite_data_files` compaction procedure with
  `strategy => 'sort'` and either a column-based `sort_order` or a
  `zorder(...)` sort_order — see
  [/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md).

# Why Sort Order Improves Pruning

Scan planning's second filtering stage (see
[/performance/performance-overview.md](/performance/performance-overview.md))
eliminates data files whose recorded min/max bounds for a column can't
satisfy the query predicate. This only eliminates files when bounds are
narrow relative to the table's overall value range for that column.
Unsorted writes (e.g. arbitrary arrival order from a streaming source)
typically produce files whose bounds span most of the domain — every
file's `[min, max]` overlaps the query predicate, so nothing gets pruned
even though the stats exist.

Sorting data by a column before/during writing packs similar values into
the same files, narrowing each file's bounds and making the same stat-based
pruning mechanism actually effective.

```sql
-- sort strategy compaction: single-column dominant order
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample',
  strategy => 'sort',
  sort_order => 'id DESC NULLS LAST,name ASC NULLS FIRST');
```

# Z-Order / Hilbert-style Clustering for Multi-Column Filters

A plain sort order only tightens bounds effectively for its *leading*
column — much like a composite index, filtering on a trailing sort column
alone gets little benefit because rows with a given trailing-column value
are still scattered across the range of the leading column.

Z-order (and similarly, Hilbert-curve clustering) addresses this by
interleaving the bits of multiple columns into a single synthetic ordering
key, then sorting by that key. The effect is that files become
simultaneously *somewhat* clustered on each participating column — not as
tightly as a dedicated single-column sort would achieve for that one
column, but usably clustered across all of them, so a query filtering on
any one (or several) of the z-ordered columns still benefits from pruning.

```sql
-- z-order strategy compaction: multiple filter columns, no single dominant one
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample',
  strategy => 'sort',
  sort_order => 'zorder(c1,c2)');
```

# When to Choose Sort vs Z-Order

| Situation | Choice |
|---|---|
| Queries almost always filter/range-scan on one specific column (e.g. `event_time`) | Sort by that column |
| Queries filter on a fixed, known combination of columns in a stable order (e.g. always `tenant_id` then `event_time`) | Multi-column sort order matching that filter order |
| Queries filter on varying combinations of 2+ columns (sometimes `c1`, sometimes `c2`, sometimes both) | Z-order on those columns |
| Queries mostly filter on the partition column already | Partitioning alone may suffice; sort/z-order adds marginal benefit within-partition |
| No consistent filter pattern / mostly full scans | Neither is likely to pay for its compaction cost — default bin-pack may be enough |

Practical note: sort/z-order is applied as a compaction strategy, so it has
the same operational cost profile as compaction generally (a Spark job
rewriting files) — see
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md)
for cadence guidance. Re-running it periodically is necessary to keep newly
written (unsorted) data clustered, since ordinary appends between
compaction runs are not sorted relative to existing files.

# Citations

[1] [Apache Iceberg — Performance: Data filtering](https://iceberg.apache.org/docs/latest/performance/#data-filtering)
[2] [Apache Iceberg — Spark Procedures: rewrite_data_files (sort/zorder options)](https://iceberg.apache.org/docs/latest/spark-procedures/#rewrite_data_files)
