---
type: Performance Guide
title: Partitioning Strategy for Performance
description: Choosing partition granularity, avoiding over- and under-partitioning, and using partition evolution to fix a bad initial choice without rewriting data.
aliases: [partition granularity, over-partitioning, under-partitioning, partition evolution, hidden partitioning, choosing partitions]
tags: [iceberg, performance, partitioning, partition-evolution]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/performance/
---

# Retrieval Notes

Read this when designing or revisiting a table's partition spec. For the
mechanics of how partition values feed scan planning, see
[/performance/performance-overview.md](/performance/performance-overview.md).
For the syntax and semantics of hidden partitioning and partition
transforms themselves, see
[/architecture/partitioning-and-hidden-partitioning.md](/architecture/partitioning-and-hidden-partitioning.md) —
this file focuses on *strategy*, not transform syntax. For fixing file-count
problems caused by a bad partitioning choice after the fact, see
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md).

# Summary

- Partitioning's whole purpose is to help the manifest-list stage of scan
  planning prune entire manifests cheaply — see
  [/performance/performance-overview.md](/performance/performance-overview.md).
  Choosing the wrong granularity undermines that without you writing any
  wrong SQL.
- **Over-partitioning** (too fine-grained) creates many small partitions,
  each write scatters data into many files, and manifest metadata balloons
  — the small-files problem, but partitioning-induced rather than
  volume-induced.
- **Under-partitioning** (too coarse) means predicates on the partition
  column don't narrow the scan much — most manifests/files still have to be
  opened, so pruning barely helps.
- Iceberg's **hidden partitioning** and **partition transforms** (e.g.
  `days(ts)`, `bucket(n, id)`) decouple the physical partition granularity
  from the columns users filter by, which gives more flexibility than
  classic Hive-style partitioning when picking granularity.
- **Partition evolution** lets you change a table's partition spec going
  forward (e.g. from `month(ts)` to `day(ts)`) without rewriting existing
  data — old data keeps its old layout, new data uses the new spec, and
  both are queried transparently.
- Because evolution avoids a full rewrite, an imperfect initial partitioning
  choice is not a permanent mistake — it's fixable, which should lower the
  stakes of the initial decision somewhat (though not eliminate the value of
  getting it close to right).

# Choosing Granularity

The goal is to size partitions so that (a) a typical query's predicate
excludes most partitions, and (b) each partition still accumulates enough
data per commit interval to produce reasonably-sized files without needing
compaction to compensate constantly.

Rules of thumb:

- Pick the partition column(s) to match your **dominant query filter**
  (e.g. `event_date` if most queries filter by day). Partitioning on a
  column nobody filters by provides no pruning benefit and only adds
  metadata overhead.
- Size granularity against **write volume per partition per commit
  interval**. If daily volume per partition is small, a daily partition
  transform will generate small files every day; consider a coarser
  transform (`month`, `week`) or rely more on
  [compaction](/maintenance/compaction-and-file-sizing.md) instead of
  chasing granularity.
- Avoid partitioning on high-cardinality columns directly (e.g. raw
  `user_id`) — use `bucket(n, user_id)` instead to bound the partition count
  while still enabling some pruning/distribution benefit.
- Multiple partition fields multiply the number of physical partitions
  (cross product) — each additional dimension increases over-partitioning
  risk unless the query workload genuinely filters on all of them together.

# Over-Partitioning

Symptoms: very high partition count relative to data volume, many
partitions with only one or a few small files, manifest counts growing
faster than expected for the data volume, and compaction runs constantly
needed to keep up.

Why it happens: partitioning by a column with too much cardinality, too
fine a time granularity (e.g. `hour` on a table with modest hourly volume),
or partitioning on multiple independent dimensions whose cross product is
large.

Mitigation: coarsen the partition transform (e.g. `hour(ts)` →
`day(ts)`), use `bucket()` instead of raw high-cardinality columns, or drop
a partition dimension that isn't earning its keep in query pruning — via
[partition evolution](#partition-evolution) rather than a full rewrite.

# Under-Partitioning

Symptoms: query predicates on what should be a filterable column don't
reduce query cost much; most manifests/files are opened regardless of the
predicate.

Why it happens: partition granularity too coarse for query patterns (e.g.
partitioning by `year` when most queries filter by `day`), or partitioning
on the wrong column entirely relative to actual query filters.

Mitigation: introduce a finer partition transform on the actually-filtered
column via evolution. Note that Iceberg's stat-based data-file filtering
(min/max bounds within a manifest) partially compensates for under-partitioning
if data happens to be well-clustered on disk — see
[/performance/sort-order-and-file-layout.md](/performance/sort-order-and-file-layout.md)
for using sort order to get pruning benefits independent of partitioning
granularity.

# Partition Evolution

Because Iceberg partition metadata is tracked per data file (not inferred
from directory paths as in Hive), a table's partition spec can change over
time without touching existing files:

- Existing data files keep the partition spec (and directory layout) that
  was active when they were written.
- New writes use the new (evolved) partition spec.
- Query planning and pruning transparently handle a table with a mix of
  old-spec and new-spec files — both is under a single logical table.

Practical implication: don't over-invest in getting the initial partition
spec perfect before shipping a table. Start with a reasonable choice aligned
to known query patterns, monitor file/partition counts and query costs, and
evolve the spec as real usage patterns emerge — this is materially cheaper
than the Hive-table equivalent of "rewrite the whole table with a new
directory layout." See
[/architecture/partitioning-and-hidden-partitioning.md](/architecture/partitioning-and-hidden-partitioning.md)
for the `ALTER TABLE ... ADD/DROP PARTITION FIELD` syntax.

# Citations

[1] [Apache Iceberg — Performance](https://iceberg.apache.org/docs/latest/performance/)
