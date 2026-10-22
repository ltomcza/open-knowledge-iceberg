---
type: Maintenance Guide
title: Maintenance Scheduling and Strategy
description: Synthesis of recommended cadence, ordering, and automation approaches for running Iceberg maintenance operations in production.
aliases: [maintenance pipeline, maintenance schedule, table maintenance strategy, operational cadence, automated compaction]
tags: [iceberg, maintenance, operations, scheduling, synthesis]
timestamp: 2026-10-22T00:00:00Z
---

# Retrieval Notes

Read this for the "how do I put it all together in production" question —
what order to run operations in, how often, and how to automate it. This
file is **guidance and synthesis**, not a verbatim rendering of the Apache
Iceberg docs — it combines the individual operation semantics documented in
[/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md),
[/maintenance/expire-snapshots.md](/maintenance/expire-snapshots.md),
[/maintenance/remove-orphan-files.md](/maintenance/remove-orphan-files.md),
and [/maintenance/rewrite-manifests.md](/maintenance/rewrite-manifests.md)
with informed operational judgment about ordering and cadence. Validate
specifics against your own workload before treating numbers here as
prescriptive.

# Summary

- There is a natural **dependency order**: compact data files → rewrite
  manifests → expire snapshots → remove orphan files. Running out of order
  either wastes work or temporarily reduces safety margins.
- Cadence should scale with **commit frequency**, not table size: streaming
  / high-commit-rate tables need much more frequent compaction and manifest
  maintenance than daily-batch tables.
- Snapshot expiration is cheap and should run on a steady schedule (e.g.
  daily) regardless of write pattern, since it bounds storage/metadata
  growth. Orphan-file removal is a less frequent sweep (weekly is usually
  enough): it needs a full storage listing, which is expensive on huge
  tables, and an unsafe `older_than` window can delete in-flight files —
  see [/maintenance/remove-orphan-files.md](/maintenance/remove-orphan-files.md).
- Compaction is the most resource-intensive operation and the one most
  worth tuning (scoping via `where`, partial-progress) rather than
  running blindly and repeatedly over the whole table.
- Automation typically means periodic jobs (Airflow/cron/orchestrator)
  calling the Spark procedures, or built-in scheduled maintenance offered
  by some managed catalogs/platforms — the underlying operations are the
  same either way.

# Recommended Ordering

1. **[Compact data files](/maintenance/compaction-and-file-sizing.md)**
   (`rewrite_data_files`) first. This is the operation that actually fixes
   the small-files problem and reduces the number of live data files/manifests
   entries going forward. Running expiration before compaction just means
   you'll be re-expiring more snapshots later as compaction itself produces
   new snapshots.
2. **[Rewrite manifests](/maintenance/rewrite-manifests.md)**
   (`rewrite_manifests`) next, since compaction changes the file set and can
   leave manifests reflecting the new layout suboptimally grouped. This step
   is metadata-only and cheap, so it's reasonable to run it after every
   significant compaction pass.
3. **[Expire snapshots](/maintenance/expire-snapshots.md)**
   (`expire_snapshots`) after compaction/manifest rewriting have settled,
   so the snapshots produced by those operations that you no longer need
   (e.g. intermediate partial-progress commits) are also eligible for
   cleanup, not just the original pre-compaction snapshots.
4. **[Remove orphan files](/maintenance/remove-orphan-files.md)**
   (`remove_orphan_files`) last. This is the final cleanup sweep for files
   that never made it into any snapshot at all (failed jobs, crashed
   writers) — it doesn't depend on the other three, but running it last
   means you're not needlessly cataloging files that a subsequent
   compaction is about to obsolete anyway.

Rationale in one line: **fix the data layout and metadata index first,
then reclaim storage for things that are now provably unreachable.**

# Recommended Cadence

| Table profile | Compaction | Rewrite manifests | Expire snapshots | Remove orphan files |
|---|---|---|---|---|
| Streaming / high-frequency micro-batch | Every 15 min – hourly, scoped to recent partitions via `where` | After each compaction pass, or hourly | Daily | Daily to weekly |
| Frequent batch (multiple loads/day) | Every few hours or after each load | After each compaction pass | Daily | Daily to weekly |
| Daily batch load | Daily, after the load completes | Daily or every few days | Daily to weekly | Weekly |
| Slow-changing / append-rarely | Weekly, or triggered by file-count/size monitoring | As needed | Weekly to monthly | Monthly |

Notes on the table above:

- These are starting points, not hard rules — the right cadence depends on
  query latency requirements, cluster cost budget, and how tolerant the
  table is of temporarily-small files.
- Streaming tables generate the most small files fastest, so they need the
  tightest compaction loop; but expensive full-table compaction runs should
  still be scoped (`where` clause, or partition-aware scheduling) rather
  than reprocessing the whole table every cycle.
- Snapshot expiration has low marginal cost and risk, and orphan removal is
  safe with the default 3-day window, so erring toward "run them on a steady
  daily/weekly schedule" is
  reasonable even if you're unsure of the ideal cadence — the main cost of
  running them too often is wasted job time, not correctness risk (subject
  to the retention-window safety notes in
  [/maintenance/remove-orphan-files.md](/maintenance/remove-orphan-files.md)).

# Automation Approaches

- **Scheduled jobs**: the most common pattern — an orchestrator (Airflow,
  Dagster, cron, a scheduled Spark job) issues the `CALL` procedures (see
  [/pyspark/spark-procedures.md](/pyspark/spark-procedures.md)) on a fixed
  schedule per table or table group.
- **Trigger-based**: kick off compaction after N commits or when the
  `files` metadata table shows small-file counts crossing a threshold,
  rather than purely time-based scheduling — more responsive for bursty
  write patterns.
- **Partial progress for large backlogs**: when catching up a
  never-before-compacted table, use `partial-progress.enabled` (see
  [/maintenance/compaction-and-file-sizing.md](/maintenance/compaction-and-file-sizing.md))
  so a multi-hour rewrite commits incrementally instead of risking losing
  all progress on a late failure.
- **Managed catalog / platform features**: some catalog implementations and
  managed lakehouse platforms offer built-in scheduled maintenance
  (auto-compaction, auto-expiration) that wraps these same underlying
  operations — check whether your catalog exposes this before building
  custom orchestration.
- **Isolate maintenance compute from write/query compute** where possible —
  compaction and manifest rewriting are resource-intensive Spark jobs and
  can compete with production query workloads if run on shared clusters
  during peak hours.

# See Also

- [/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md) — concrete commands for the sequence above after a big row-level update.
- [/performance/high-volume-table-playbook.md](/performance/high-volume-table-playbook.md) — example daily schedule for a 100M–1B rows/day table.

# Citations

[1] [Apache Iceberg — Maintenance](https://iceberg.apache.org/docs/latest/maintenance/)
[2] [Apache Iceberg — Spark Procedures](https://iceberg.apache.org/docs/latest/spark-procedures/)

Note: the ordering, cadence table, and automation guidance above are this
document's own synthesis of production best practice, not a direct
transcription of the cited sources.
