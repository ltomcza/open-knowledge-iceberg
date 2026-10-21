---
type: Maintenance Guide
title: Rewrite Manifests
description: Why manifest files fragment over time and how rewrite_manifests re-groups them to speed up scan planning and pruning.
aliases: [rewrite_manifests, manifest rewriting, manifest fragmentation, scan planning performance, manifest compaction]
tags: [iceberg, maintenance, manifests, scan-planning, performance]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/maintenance/
---

# Retrieval Notes

Read this when scan planning feels slow despite data files already being
well-sized (i.e. after ruling out the small-files problem covered in
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md)).
For the exact `CALL` syntax and every argument, see
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) (procedure:
`rewrite_manifests`). For how manifests fit into Iceberg's metadata tree
generally, see [/architecture/](/architecture/) (manifest list / manifest
file concepts).

# Summary

- Manifests are the metadata layer that indexes data files: each manifest
  lists a set of data files plus their partition values and column stats,
  and the manifest list indexes the manifests for a snapshot.
- Manifests are automatically compacted **in the order they're added** on
  writes — good when write order matches query filter order (e.g. hourly
  writes + time-range queries), but this alignment breaks down over many
  commits or when write pattern != read pattern.
- Symptom of manifest fragmentation: many small manifests, or manifests
  whose partition-value ranges overlap heavily, forcing scan planning to
  open more manifests than necessary even after partition pruning.
- `rewrite_manifests` re-groups data file entries into new, better-organized
  manifest files — it does not touch data files at all, only metadata.
- Can optionally cluster (`sort_by`) manifests by specific partition
  transforms to concentrate metadata for frequently-filtered fields.
- This is a metadata-only operation and cheap relative to data compaction —
  safe to run more frequently than
  [compaction](/maintenance/compaction-and-file-sizing.md) if commit volume
  is high.

# Why Manifests Fragment

Every commit that adds/removes data files potentially adds a new manifest
(or extends existing ones, depending on merge settings like
`commit.manifest-merge.enabled` / `commit.manifest.min-count-to-merge`).
Automatic compaction on write keeps manifests roughly in commit order. This
works well when writes are naturally aligned to query patterns — e.g. data
arrives and is queried by the same time range. It works poorly when:

- Write pattern is out of sync with read pattern (e.g. writes arrive
  unordered but reads always filter on a specific partition field).
- High commit frequency (streaming, frequent micro-batches) produces many
  small manifests faster than automatic merge can consolidate them usefully
  for read-side pruning.
- Backfills or out-of-order data insertion scatter partition-value ranges
  across many manifests, so the manifest list can no longer cheaply exclude
  most manifests for a given predicate.

# How It Improves Planning / Read Performance

Scan planning works in two stages: filter manifests using the partition
value ranges recorded in the manifest list, then read the surviving
manifests to get candidate data files (see
[/performance/performance-overview.md](/performance/performance-overview.md)
for the full scan-planning mechanism). If manifests are poorly organized —
overlapping ranges, many tiny manifests — more manifests survive the first
filtering stage and have to be opened and scanned, which is pure planning
overhead before any data file is even touched.

`rewrite_manifests` regroups data file entries into cleanly organized
manifests (by default aligned to the partition spec), so the manifest list
index becomes tight and effective again — fewer manifests need to be opened
for a typical query.

```sql
-- realign manifests with table partitioning (defaults)
CALL catalog_name.system.rewrite_manifests('db.sample');

-- cluster manifest entries by a specific, frequently-filtered field
CALL catalog_name.system.rewrite_manifests(table => 'db.sample', sort_by => array('category'));
```

`sort_by` lets you deliberately optimize for your dominant query filter
pattern rather than accepting the default partition-spec-order grouping —
useful when queries consistently filter on a field that isn't the leading
partition column.

# Operational Notes

- Metadata-only — does not rewrite or move data files, so it's much
  cheaper than `rewrite_data_files` and safe to run more often.
- Invalidates cached Spark query plans referencing the table (per the
  procedure's own documented side effect) — expect a planning-cache reset
  on next query after running it.
- Full argument reference (`use_caching`, `spec_id`) is in
  [/pyspark/spark-procedures.md](/pyspark/spark-procedures.md).

# Citations

[1] [Apache Iceberg — Maintenance: Rewrite Manifests](https://iceberg.apache.org/docs/latest/maintenance/#rewrite-manifests)
[2] [Apache Iceberg — Spark Procedures: rewrite_manifests](https://iceberg.apache.org/docs/latest/spark-procedures/#rewrite_manifests)
[3] [Apache Iceberg — Performance: Metadata filtering](https://iceberg.apache.org/docs/latest/performance/#metadata-filtering)
