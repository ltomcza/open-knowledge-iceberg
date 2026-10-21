---
type: Performance Guide
title: Large-Scale MERGE / UPDATE Tuning (Spark)
description: How to make MERGE INTO / UPDATE / DELETE fast on very large Iceberg tables (billions of rows, hundreds of millions of changes per day) — COW vs MOR choice, filter pushdown via the ON clause, bounded merges, storage-partitioned joins, join strategy, distribution modes, delete granularity, and v3 deletion vectors.
aliases: [merge into performance, slow merge iceberg, upsert billions of rows, bulk update iceberg, merge-on-read at scale, iceberg merge tuning, update huge iceberg table, shuffle hash join merge]
tags: [iceberg, performance, spark, merge-into, update, delete, mor, cow, spj, tuning]
timestamp: 2026-10-21T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-writes/
---

# Retrieval Notes

Read this when a `MERGE INTO`, `UPDATE`, or `DELETE` against a big Iceberg
table is too slow or too expensive. It covers the write job itself. For SQL
syntax and clause semantics see
[/pyspark/merge-into-and-row-level-operations.md](/pyspark/merge-into-and-row-level-operations.md).
For the shuffle-free join setup in detail see
[/performance/storage-partitioned-joins.md](/performance/storage-partitioned-joins.md).
For the cleanup to run *after* a big update (compacting delete files and
restoring read speed) see
[/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).
For how delete files work internally see
[/architecture/row-level-deletes.md](/architecture/row-level-deletes.md).

This file combines the official Iceberg docs with practitioner reports
(Ancestry/AWS, Expedia, ZeroToOne, Cloudera, Akashdeep Gupta). The
benchmark numbers come from those reports and won't transfer directly to
your workload. Check them against your own Spark UI and `EXPLAIN` output.

# Summary

- A `MERGE` has three expensive phases: **read** (scanning the target),
  **join/merge rows** (shuffle and sort of both sides), and **write**
  (shuffle/sort before writing). Shuffles usually dominate the runtime.
- **Choose COW vs MOR per table and per operation.** Merge-on-read
  (`write.merge.mode` / `write.update.mode` / `write.delete.mode` =
  `merge-on-read`) writes small delete files instead of rewriting whole
  data files. It is much cheaper when changes are spread thinly across many
  files. Copy-on-write is better when an update rewrites most of the rows in
  the files it touches, or when reads are latency-critical and you can't
  compact right after the write.
- **Only predicates in the `ON` clause are pushed down** to the target
  scan. Conditions in `WHEN MATCHED AND ...` are not. Put partition filters
  and key ranges in `ON`, or the target is scanned in full.
- **Bound the merge.** Compute min/max (or the distinct partition values)
  of the source batch first, then add them to `ON` as literals. Iceberg can
  then prune files using its min/max stats.
- **Storage-partitioned join (SPJ)** removes the target-side shuffle when
  source and target share the same partitioning (for example
  `bucket(N, key)`). In the ZeroToOne case, SPJ plus a `SHUFFLE_HASH` hint
  took a 2-billion-row merge from about 60 minutes to about 4.
- **Distribution modes** (`write.merge.distribution-mode` etc.) trade
  write speed (`none`) against file count and layout (`hash`/`range`).
  `none` is only safe when each task writes one partition, or when you
  compact frequently.
- **Delete granularity `file`** (the Spark write default in recent
  releases) and **format v3 deletion vectors** keep merge-on-read
  delete files targeted and cheap to read. Delete files still need regular
  compaction.

# COW vs MOR for Bulk Updates

| Signal | Prefer copy-on-write | Prefer merge-on-read |
|---|---|---|
| Fraction of rows changed *per touched file* | High (most rows in the file change) | Low (a few rows per file) |
| Number of files touched per batch | Few | Many (changes spread across partitions) |
| Update frequency | Rare, large batch rewrites | Frequent (hourly or continuous) |
| Read SLA right after the write | Strict | Tolerant, or compaction runs before readers arrive |
| Can you run compaction after each load? | Not needed | Required |

```sql
-- Per-operation modes. These are independent table properties.
ALTER TABLE prod.db.events SET TBLPROPERTIES (
  'write.merge.mode'  = 'merge-on-read',
  'write.update.mode' = 'merge-on-read',
  'write.delete.mode' = 'merge-on-read'
);
```

Practitioner data points:

- **Ancestry** (100 billion rows, about 7 million changes per hour):
  default COW was "too slow and expensive". Switching `write.merge.mode`
  to MOR made the hourly merge workable, at the cost of slower reads until
  compaction ran. Combined with the other techniques here, they reported a
  75% cost reduction.
- **Cloudera** enables MOR by default for its customers. Spark writes
  *position* deletes. It can read equality deletes but does not write them.
- A hybrid is common: write each day's merge with MOR, then run
  compaction (which folds deletes into data files) before the read-heavy
  window. See
  [/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).

# Phase 1 — Read: Push Down and Bound the Target Scan

Filters in `WHEN MATCHED AND ...` / `WHEN NOT MATCHED AND ...` are applied
*after* the join. Only the `ON` clause reaches the Iceberg scan.

```sql
-- Bad: the target is scanned in full and the partition filter is applied late
MERGE INTO prod.db.events t
USING updates s
ON t.event_id = s.event_id
WHEN MATCHED AND t.event_date = DATE '2026-10-20' THEN UPDATE SET *;

-- Good: partition and range predicates in ON are pushed into the scan
MERGE INTO prod.db.events t
USING updates s
ON  t.event_date = DATE '2026-10-20'
AND t.event_date = s.event_date
AND t.event_id   = s.event_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
```

**Bounded merge (dynamic literals).** If the batch's key range or partition
set changes from run to run, compute it first and inject it as literals.
This is Ancestry's pattern:

```python
from pyspark.sql import functions as F

src = spark.table("prod.db.updates_staging")
b = src.agg(F.min("id").alias("lo"), F.max("id").alias("hi"),
            F.collect_set("event_date").alias("days")).first()
days = ",".join(f"DATE '{d}'" for d in b["days"])

spark.sql(f"""
MERGE INTO prod.db.events t
USING prod.db.updates_staging s
ON  t.event_date IN ({days})
AND t.id BETWEEN {b['lo']} AND {b['hi']}
AND t.event_date = s.event_date
AND t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")
```

Range pruning only helps if the target's files are *clustered* on that key
(sort order or z-order). Otherwise every file's min/max range covers the
whole key space. See
[/performance/sort-order-and-file-layout.md](/performance/sort-order-and-file-layout.md).

Spark's runtime filtering (dynamic partition pruning) can also prune the
target from the source side automatically. Check `EXPLAIN` for
`runtimeFilters` on the target `BatchScan`. The literal approach above is
the more reliable of the two.

# Phase 2 — Join: Avoid Shuffling and Sorting the Big Side

1. **Storage-partitioned join.** If the target is bucketed on the merge
   key, for example `PARTITIONED BY (days(ts), bucket(256, id))`, and the
   staging table is an Iceberg table with the *same* spec, Spark can join
   bucket to bucket without an `Exchange` on either side. The full config
   and requirements are in
   [/performance/storage-partitioned-joins.md](/performance/storage-partitioned-joins.md).
2. **Shuffle hash join instead of sort-merge join.** Even with SPJ, Spark
   sorts each bucket for a sort-merge join. For a small source and a huge
   target, hashing the small side removes the sort of the big side
   entirely:

   ```sql
   MERGE INTO prod.db.visits t
   USING /*+ SHUFFLE_HASH(s) */ daily_incremental s
   ON t.ad_id = s.ad_id
   WHEN MATCHED THEN UPDATE SET *
   WHEN NOT MATCHED THEN INSERT *;
   ```

   ```properties
   spark.sql.join.preferSortMergeJoin=false
   spark.sql.shuffle.partitions=256            # match the bucket count
   ```

   **Gotcha (ZeroToOne):** Spark ignores the hint when it estimates the
   build side won't fit in memory, and it uses
   `spark.sql.autoBroadcastJoinThreshold` for that estimate. They had to
   disable AQE (`spark.sql.adaptive.enabled=false`) *and* raise
   `spark.sql.autoBroadcastJoinThreshold` (to 512 MB, for about 200 MB per
   build partition) before the plan was stable from run to run. Disabling
   AQE affects every stage, so scope it to the merge job's session.
3. **Broadcast** the source when it is genuinely small (well under the
   executor memory budget). This also removes the target-side shuffle.
4. **Dedupe the source first.** Only one source row may match a target
   row, or the merge fails. A `ROW_NUMBER()` window over the key in the
   staging step is cheaper than failing a multi-hour merge.

# Phase 3 — Write: Distribution Mode, Fanout, File Sizes

Per-operation distribution properties (they fall back to engine defaults
when unset):

| Property | Controls |
|---|---|
| `write.distribution-mode` | INSERT / append |
| `write.merge.distribution-mode` | MERGE |
| `write.update.distribution-mode` | UPDATE |
| `write.delete.distribution-mode` | DELETE |
| `spark.sql.iceberg.distribution-mode` (session) | Overrides all of the above for the session |

| Mode | Write cost | Effect on files | Use for bulk merges when |
|---|---|---|---|
| `none` | Cheapest, no pre-write `Exchange` | Each task may write to every partition it sees, giving many small files | The merge touches one or a few partitions, *and* compaction follows |
| `hash` | One shuffle by partition key | About one file set per partition per task, with sizes coalesced by AQE | Default choice for multi-partition merges |
| `range` | Sample plus shuffle, most expensive | Globally sorted output, best pruning | The table has a sort order and readers depend on it |

- **Fanout writer** (`write.spark.fanout.enabled=true`) removes the local
  sort before the write by keeping one open file per partition per task.
  It uses more executor memory.
- **Output file size under AQE.** With `hash`/`range`, task size is
  driven by `spark.sql.adaptive.advisoryPartitionSizeInBytes` (or
  `spark.sql.iceberg.advisory-partition-size`). This is *shuffle* bytes,
  which are row-based and compress less than columnar Parquet, so set it
  *larger* than `write.target-file-size-bytes` to get files near the
  target size.
- For MOR, delete files have their own target size:
  `write.delete.target-file-size-bytes` (64 MB default).

# Delete Granularity and Deletion Vectors (MOR)

| Setting | Values | Notes |
|---|---|---|
| `write.delete.granularity` (table) / `delete-granularity` (Spark write option) | `file` / `partition` | `partition` packs deletes for many data files into one delete file: fewer files, but each reader also loads deletes that don't apply to its file. `file` writes one delete file per data file: targeted reads, more files, needs more aggressive delete compaction. Recent Spark writes default to `file` (check your Iceberg version's docs). Applies to position deletes only. |
| `write.delete.maintain-during-write` / Spark conf `maintain-position-deletes` | default on | Spark merges a data file's existing position deletes into the new delete file it writes ("minor compaction" during the write). The data-to-delete-file mapping is broadcast to executors, which can raise memory use on tables with millions of files. |
| `format-version = 3` | — | Position deletes become **deletion vectors**: Roaring bitmaps in Puffin files, at most one per data file per snapshot, merged on every write. An AWS EMR benchmark (EMR 7.10, Spark 3.5.5) showed 55% faster deletes, about 74% smaller delete files, and 23–28% faster reads than v2 position deletes. Make sure *every* engine that reads the table supports v3 before upgrading. |
| `spark.sql.iceberg.executor-cache.enabled` | `true` | Caches delete files on executors (max 64 MB per entry and 128 MB in total by default). Raise `executor-cache.max-total-size` when many tasks share the same delete files. |

Whatever the granularity, **delete files must still be compacted
regularly**. Read cost grows with every MOR commit that isn't compacted.

# Concurrency and Commit Safety

- `write.merge.isolation-level` / `write.update.isolation-level` /
  `write.delete.isolation-level` default to `serializable`. `snapshot` is
  more permissive (it only checks for conflicting deletes). Use it when
  concurrent appends to the same partitions are expected and acceptable.
- These table properties do **not** cover `overwritePartitions()` /
  `overwrite()` / `INSERT OVERWRITE`. Those are unchecked unless you pass
  the `isolation-level` and `validate-from-snapshot-id` write options. If
  *every* row of a partition changes, replacing the partition is usually
  the better plan. See
  [/performance/full-partition-rewrite-and-safe-overwrite.md](/performance/full-partition-rewrite-and-safe-overwrite.md).
- Long merges conflict with concurrent compaction of the *same*
  partitions. Schedule compaction on partitions the merge has finished
  with, or run it right after the merge in the same orchestration DAG. See
  [/architecture/reliability-and-concurrency.md](/architecture/reliability-and-concurrency.md).
- For audited pipelines, stage the batch with **Write-Audit-Publish**
  (`write.wap.enabled`, `spark.wap.branch`), validate it, then fast-forward
  `main`. Ancestry stages its changes in a WAP-audited Iceberg table that
  also shares the target's partitioning, so it can use SPJ. See
  [/architecture/branching-and-tagging.md](/architecture/branching-and-tagging.md).
- Audit merge sizes with the Spark 4.1+ snapshot-summary counters
  (`spark.merge-into.num-target-rows-*`) to catch accidental full-table
  rewrites.

# Checklist for a Slow MERGE

1. `EXPLAIN` the merge. Is there a `BatchScan` of the target *without*
   pushed filters? Move the predicates into `ON`.
2. Is there an `Exchange` on the target side? Set up SPJ (same partition
   spec on both sides, partition columns in `ON`, SPJ configs).
3. Is there a `Sort` on the target side? Use a shuffle-hash or broadcast
   join.
4. Is the write `Exchange` expensive, and does the merge touch only a few
   partitions? Consider `write.merge.distribution-mode=none` plus
   compaction afterwards.
5. Does every run rewrite huge amounts of data under COW? Switch that
   operation to MOR and add post-update compaction.
6. Are reads slow after the merge? Run the
   [post-update maintenance runbook](/maintenance/post-update-maintenance-runbook.md).

# Citations

[1] [Apache Iceberg — Spark Writes (distribution modes, controlling file sizes)](https://iceberg.apache.org/docs/latest/spark-writes/)
[2] [Apache Iceberg — Configuration: write properties](https://iceberg.apache.org/docs/latest/configuration/)
[3] [Apache Iceberg — Spark Configuration (SQL options, write options)](https://iceberg.apache.org/docs/latest/spark-configuration/)
[4] [AWS Big Data Blog — How Ancestry optimizes a 100-billion-row Iceberg table (2025)](https://aws.amazon.com/blogs/big-data/how-ancestry-optimizes-a-100-billion-row-iceberg-table/)
[5] [ZeroToOne — From 60 Minutes to 4: Optimizing Spark MERGE INTO on a 2 Billion Row Iceberg Table (2026)](https://blog.platform.zerotoone.ai/blog/spark-merge-optimization-from-60-to-4-minutes/)
[6] [Akashdeep Gupta — Optimizing Iceberg MERGE Statements (2025)](https://www.guptaakashdeep.com/optimizing-iceberg-merge-statements/)
[7] [Cloudera — Optimization Strategies for Iceberg Tables (2024)](https://www.cloudera.com/blog/technical/optimization-strategies-for-iceberg-tables.html)
[8] [Iceberg Javadoc — DeleteGranularity](https://iceberg.apache.org/javadoc/latest/org/apache/iceberg/deletes/DeleteGranularity.html)
[9] [apache/iceberg PR #11273 — Merge new position deletes with old deletes during writing](https://github.com/apache/iceberg/pull/11273)
[10] [AWS Big Data Blog — Unlock the power of Apache Iceberg v3 deletion vectors on Amazon EMR (2025)](https://aws.amazon.com/blogs/big-data/unlock-the-power-of-apache-iceberg-v3-deletion-vectors-on-amazon-emr/)
