---
type: Playbook
title: Post-Update Maintenance Runbook
description: Step-by-step maintenance to run after a massive MERGE/UPDATE/DELETE to restore Iceberg read performance — diagnose with metadata tables, compact data and delete files, remove dangling deletes, rewrite manifests, expire snapshots and clean orphans at scale, refresh statistics.
aliases: [maintenance after merge, after bulk update, restore read performance iceberg, delete file compaction, cleanup after upsert, iceberg runbook, post-merge compaction]
tags: [iceberg, maintenance, playbook, compaction, deletes, mor, performance, spark]
timestamp: 2026-10-21T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-procedures/
---

# Retrieval Notes

Read this right after (or when scheduling the job that follows) a large
row-level change on an Iceberg table. It is an ordered, copy-paste-able
sequence. For why each operation exists, see the concepts it links to
([compaction](/maintenance/compaction-and-file-sizing.md),
[rewrite manifests](/maintenance/rewrite-manifests.md),
[expire snapshots](/maintenance/expire-snapshots.md),
[orphan files](/maintenance/remove-orphan-files.md)). For general cadence
see [/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md).
For making the update itself faster see
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md).

The procedure options come from the official Spark procedures docs. The
ordering, thresholds, and scale tips are synthesized from AWS prescriptive
guidance, the Ancestry case study, and apache/iceberg issues and PRs.
Treat the numbers as starting points.

# Summary

1. **Diagnose**: query `files`, `delete_files`, `partitions`, and
   `snapshots` to find which partitions now carry small files and delete
   files.
2. **Compact data files** in the affected partitions with
   `rewrite_data_files`, using delete-aware thresholds
   (`delete-file-threshold`, `delete-ratio-threshold`) so data files
   shadowed by deletes are rewritten and their deletes applied.
3. **Compact the remaining position delete files** with
   `rewrite_position_delete_files`. This merges small delete files and
   drops dangling records.
4. **Rewrite manifests** so scan planning works over well-clustered
   metadata again.
5. **Expire snapshots** with `max_concurrent_deletes` and `stream_results`.
   Until you expire, the pre-update files are still referenced and still
   cost storage.
6. **Remove orphan files** periodically, keeping a safety window.
7. **Refresh statistics** (`compute_table_stats` / `compute_partition_stats`)
   for cost-based optimization.

Under copy-on-write, step 3 is unnecessary and step 2 is mainly about
small files. Under merge-on-read, steps 2 and 3 matter most for read
performance.

# Step 0 — Diagnose What the Update Did

```sql
-- Snapshot produced by the update: operation, files added/removed, delete counts
SELECT committed_at, operation, summary
FROM prod.db.events.snapshots ORDER BY committed_at DESC LIMIT 5;

-- Data-file health per partition: count, average size, small-file count
SELECT partition,
       count(*)                                   AS data_files,
       round(avg(file_size_in_bytes)/1048576)     AS avg_mb,
       sum(CASE WHEN file_size_in_bytes < 128*1048576 THEN 1 ELSE 0 END) AS small_files
FROM prod.db.events.data_files
GROUP BY partition ORDER BY small_files DESC;

-- Delete-file load per partition (MOR tables)
SELECT partition, content, count(*) AS delete_files, sum(record_count) AS deleted_rows
FROM prod.db.events.delete_files
GROUP BY partition, content ORDER BY delete_files DESC;

-- Partition summary including delete counts
SELECT partition, record_count, file_count,
       position_delete_record_count, equality_delete_record_count
FROM prod.db.events.partitions;
```

Use the results to build a `where` predicate for the next steps (for
example, only the days the update touched). Rewriting the whole table every
night is the most common avoidable cost.

# Step 1 — Compact Data Files (Delete-Aware)

```sql
CALL prod.system.rewrite_data_files(
  table   => 'db.events',
  strategy => 'binpack',            -- or 'sort' to restore clustering (more expensive)
  where   => "event_date >= DATE '2026-10-14'",
  options => map(
    'delete-file-threshold',              '1',     -- rewrite any data file that has a delete file
    'delete-ratio-threshold',             '0.1',   -- or >10% of its rows deleted (default 0.3)
    'remove-dangling-deletes',            'true',  -- extra commit that drops deletes now pointing at nothing
    'partial-progress.enabled',           'true',
    'partial-progress.max-commits',       '20',
    'max-concurrent-file-group-rewrites', '20',    -- default 5, too low for many partitions
    'max-file-group-size-bytes',          '53687091200',  -- 50 GB per group; lower it to avoid OOM
    'rewrite-job-order',                  'bytes-desc'
  ));
```

Key options and why they matter after an update:

| Option | Default | Post-update use |
|---|---|---|
| `delete-file-threshold` | 2147483647 (effectively off) | **Off by default.** Set it low (1–3) or the file-count trigger never fires for delete-heavy files |
| `delete-ratio-threshold` | 0.3 | Lower it to clean up files with moderate delete ratios |
| `remove-dangling-deletes` | false | Drops delete files that no longer apply to any live data file. Does not cover global equality deletes |
| `rewrite-all` | false | Ancestry uses `true` to fold every delete into data files, at a high compute cost. Scope it with `where` |
| `max-concurrent-file-group-rewrites` | 5 | Ancestry runs 100 across thousands of partitions. Lower it for partitions that OOM |
| `max-file-group-size-bytes` | 100 GB | Each group is rewritten (and sorted) independently. Lower it to bound memory, raise it to the partition size for a full-partition sort |
| `partial-progress.enabled` | false | Commits groups as they finish. A conflict or failure only loses that group's work |
| `cache-delete-files` | false | Enable when the same delete file covers many data files (common with equality deletes) |
| `use-starting-sequence-number` | true | Keep the default so compaction doesn't invalidate deletes committed concurrently |

To avoid conflicts with writers, compact **cold partitions** (exclude the
ones still being written via `where`). This leaves only metadata conflicts,
which Iceberg resolves automatically. If late data may land in partitions
being compacted, keep `partial-progress` on.

# Step 2 — Compact Position Delete Files

Run this when delete files remain that the data rewrite didn't remove (for
example, data files below the delete thresholds).

```sql
CALL prod.system.rewrite_position_delete_files(
  table   => 'db.events',
  where   => "event_date >= DATE '2026-10-14'",
  options => map('min-input-files', '2', 'partial-progress.enabled', 'true'));
```

- Merges small delete files to `write.delete.target-file-size-bytes`
  (64 MB) and filters out records that point at data files that are no
  longer live.
- On **format v3**, deletion vectors are kept at one per data file and
  merged during writes, so this step matters less. Data-file compaction is
  still required to physically drop deleted rows.

# Step 3 — Rewrite Manifests

```sql
CALL prod.system.rewrite_manifests(table => 'db.events', use_caching => false);
```

Big merges and compactions leave many manifests that are poorly clustered
by partition. Rewriting them restores fast, partition-pruned planning (the
Iceberg community reports about 1 s planning on 20M+ file tables when
manifests are well clustered). It is metadata-only and cheap. Run it after
every significant compaction. Set `use_caching => false` on very large
tables to avoid executor memory pressure.

# Step 4 — Expire Snapshots at Scale

```sql
CALL prod.system.expire_snapshots(
  table                  => 'db.events',
  older_than             => TIMESTAMP '2026-10-14 00:00:00',
  retain_last            => 5,
  max_concurrent_deletes => 20,    -- thread pool for file deletes; serial by default
  stream_results         => true); -- stream deleted file paths to the driver; avoids driver OOM
```

- Until the pre-update snapshots are expired, the files the update
  replaced are still referenced. Storage doesn't shrink, and metadata keeps
  growing.
- Ancestry runs this with `retain_last => 1, max_concurrent_deletes => 20`.
  Pick retention to match your time-travel and rollback needs. The table
  setting `history.expire.max-snapshot-age-ms` interacts with `retain_last`.
- If it fails with "Cannot broadcast the table that is larger than 8GB",
  set `spark.sql.autoBroadcastJoinThreshold=-1` for this job (see
  apache/iceberg#3703).
- The first expiration on a table that was never maintained can be very
  heavy. Expire in age slices (e.g. 30 days → 14 → 7) rather than all at
  once.

# Step 5 — Remove Orphan Files (Less Often)

```sql
CALL prod.system.remove_orphan_files(
  table                  => 'db.events',
  older_than             => TIMESTAMP '2026-10-18 00:00:00',  -- at least 3 days back, past any in-flight write
  max_concurrent_deletes => 20);
```

- Do a dry run first (`dry_run => true`) on a new table.
- On tables with tens of millions of files, newer Iceberg releases add a
  `stream-results` option for this action and are adding parallel prefix
  listing (apache/iceberg PR #14278, PR #16933). On older versions, use a
  larger driver. S3 503 throttling during listing and deletes is mitigated
  with `s3.retry.num-retries` / `s3.retry.max-wait-ms`.
- Weekly is usually enough. Orphans come from failed writes, not from
  successful updates.

# Step 6 — Refresh Statistics

```sql
CALL prod.system.compute_table_stats(table => 'db.events');      -- NDV sketches into Puffin
CALL prod.system.compute_partition_stats(table => 'db.events');
```

Spark's CBO uses these (`spark.sql.iceberg.report-column-stats=true`,
with CBO enabled) to choose join strategies, including whether a later
merge's source side is small enough to broadcast or hash.

# Putting It in a DAG

```
load/merge (MOR) ──► compact data (where=touched days, delete thresholds)
                 ──► rewrite_position_delete_files (same scope)
                 ──► rewrite_manifests
                 ──► expire_snapshots (daily)
                 ──► compute_table_stats (daily)
remove_orphan_files ── weekly, separate schedule
```

- Run the compaction steps **before** the read-heavy window. With MOR,
  the period between the merge and compaction is when reads are slowest.
- Give maintenance its own cluster or queue so it doesn't compete with the
  ingest job or with queries.
- On AWS, Glue Data Catalog table optimizers can run compaction,
  expiration, and orphan cleanup automatically. Custom jobs like the one
  above remain the norm at extreme scale (as with Ancestry).

# Citations

[1] [Apache Iceberg — Spark Procedures (rewrite_data_files, rewrite_position_delete_files, rewrite_manifests, expire_snapshots, remove_orphan_files, compute_table_stats)](https://iceberg.apache.org/docs/latest/spark-procedures/)
[2] [AWS Prescriptive Guidance — Iceberg compaction best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/apache-iceberg-on-aws/best-practices-compaction.html)
[3] [AWS Big Data Blog — How Ancestry optimizes a 100-billion-row Iceberg table (2025)](https://aws.amazon.com/blogs/big-data/how-ancestry-optimizes-a-100-billion-row-iceberg-table/)
[4] [apache/iceberg issue #3703 — DeleteOrphanFiles or ExpireSnapshots out of memory](https://github.com/apache/iceberg/issues/3703)
[5] [apache/iceberg issue #4007 — max_concurrent_deletes for remove_orphan_files and expire_snapshots](https://github.com/apache/iceberg/issues/4007)
[6] [apache/iceberg PR #14278 — stream-results option for remove orphan files](https://github.com/apache/iceberg/pull/14278)
[7] [apache/iceberg PR #16933 — Parallelize RemoveOrphanFiles prefix listing](https://github.com/apache/iceberg/pull/16933)
[8] [apache/iceberg PR #8123 — Spark distributed planning (planning benchmarks)](https://github.com/apache/iceberg/pull/8123)
