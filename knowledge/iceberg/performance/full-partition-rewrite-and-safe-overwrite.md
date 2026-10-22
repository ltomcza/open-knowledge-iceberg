---
type: Playbook
title: Full-Partition Rewrite and Conflict-Safe Overwrite (Spark)
description: How to correct columns for every row of a large partition (hundreds of millions of rows) by replacing the partition instead of row-level UPDATE/MERGE, and how to make that overwrite fail safely when concurrent writers changed the partition — isolation-level and validate-from-snapshot-id write options, the overwrite APIs and their gotchas, verification, retries, and WAP staging.
aliases: [rewrite whole partition, backfill correction, recompute day partition, overwritePartitions isolation, validate-from-snapshot-id, INSERT INTO REPLACE WHERE iceberg, safe insert overwrite, check data changed before overwrite, update all rows in partition, historical correction iceberg]
tags: [iceberg, performance, spark, overwrite, backfill, concurrency, isolation, correction, wap]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-configuration/#write-options
---

# Retrieval Notes

Read this when a job must recompute some columns for **every row** of one or
more partitions (for example four columns for a whole day of about 500M rows).
The questions it answers are which write path to use and how to stop the
overwrite from silently dropping rows that another writer added while the job
was running.

For MERGE/UPDATE tuning, where only *some* rows change, see
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md).
For overwrite syntax basics see
[/pyspark/writing-data.md](/pyspark/writing-data.md). For the OCC protocol
underneath see
[/architecture/reliability-and-concurrency.md](/architecture/reliability-and-concurrency.md).
For the clean-up afterwards see
[/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).

Researched via Exa on 2026-10-21 from the Iceberg docs, the Iceberg Spark
source (`SparkWrite.java`), apache/iceberg PRs #2925 and #4293, SPARK-40956,
and practitioner write-ups. Option names and defaults move between releases.
Check them against the docs for the Iceberg version you run.

# Summary

- When **every row** of a partition changes, rewriting the partition costs
  about the same as a copy-on-write UPDATE and far less than merge-on-read.
  Under MOR an all-rows update writes a delete entry for every row *plus* a
  full new copy of the data. Never run it that way.
- There are three viable write paths:
  1. `df.writeTo(t).overwritePartitions()`: dynamic replacement of every
     partition present in `df`.
  2. `df.writeTo(t).overwrite(condition)`, or SQL
     `INSERT INTO t REPLACE WHERE <cond> SELECT ...` (Spark 3.4+): replaces
     the rows matching an explicit filter.
  3. A **copy-on-write `UPDATE ... SET ... WHERE <partition predicate>`**,
     when the new values can be computed in SQL. It gets serializable
     conflict checks automatically.
- **Overwrites are *not* conflict-checked by default.** The Spark write
  option `isolation-level` defaults to `null`, which means no checks. The
  table properties `write.update.isolation-level` /
  `write.merge.isolation-level` / `write.delete.isolation-level` only govern
  `UPDATE` / `MERGE` / `DELETE`. They do **not** protect
  `overwritePartitions()`, `overwrite()` or `INSERT OVERWRITE`.
- For a safe overwrite, pin the snapshot you read, then pass
  `isolation-level=serializable` and `validate-from-snapshot-id=<that id>`
  on the write. A concurrent append or delete in the target partition then
  makes the commit fail with `ValidationException`.
- **A `ValidationException` is never retried automatically.** Only
  `CommitFailedException` is retried, and those retries re-apply the same
  files. The job itself must re-read the latest snapshot, rebuild the
  partition and try again.
- Verify the result from the **snapshot summary**. For a pure column
  correction, `deleted-records` should equal `added-records`.

# Choosing the Write Path

| Path | Good for | Conflict protection | Gotchas |
|---|---|---|---|
| `UPDATE t SET c1=..., c4=... WHERE event_date = DATE '...'` with `write.update.mode=copy-on-write` | New values computable from the row itself, or a correlated subquery | Automatic. `write.update.isolation-level` (default `serializable`), validated from the scan snapshot and scoped to the scan filter | Under MOR it is the worst case. Switch the table (or that operation) to COW first. The mode is a table property, not a per-statement option. |
| `overwritePartitions()` | Recomputed partition from a DataFrame (joins with a correction set) | Opt in with `isolation-level` + `validate-from-snapshot-id`. Checked per **partition**: any added or deleted file in that partition conflicts | An **empty DataFrame commits nothing** (Spark logs "Dynamic overwrite is empty, skipping commit"). Which partitions are replaced follows the *current* spec, so after partition evolution (day→hour) old-spec files for the same day can survive and duplicate rows. |
| `overwrite(condition)` / `INSERT INTO ... REPLACE WHERE` | Exact, explicit scope such as `event_ts` in `[day, day+1)` | Opt in with the same options (DataFrame only). Checked per **file** matching the filter, which is narrower than `overwritePartitions` | An **empty DataFrame deletes the matching rows**. Rows in `df` outside the condition are inserted anyway. |
| `INSERT OVERWRITE` (SQL) | Ad-hoc fixes | No documented way to pass `isolation-level` from SQL, so treat it as unchecked | Static mode without a `PARTITION` clause **replaces the whole table**. A `PARTITION` clause cannot name hidden partitions such as `days(ts)`. |

`INSERT OVERWRITE ... REPLACE WHERE` is **not** valid Spark/Iceberg syntax.
The Spark 3.4+ form is `INSERT INTO t REPLACE WHERE <cond> SELECT ...`, and
Iceberg executes it as an overwrite-by-filter. The `REPLACE WHERE` /
`replaceWhere` docs you may find online are Delta Lake's, and their
constraint checks do not apply to Iceberg.

# Conflict-Safe Overwrite Recipe (PySpark)

```python
from pyspark.sql import functions as F

TABLE = "catalog.db.fact_table"
day_start, day_end = "2026-10-20 00:00:00", "2026-10-21 00:00:00"
day_filter = (F.col("event_ts") >= F.lit(day_start).cast("timestamp")) & \
             (F.col("event_ts") <  F.lit(day_end).cast("timestamp"))

def rebuild_and_replace(max_attempts=3):
    for attempt in range(1, max_attempts + 1):
        # 1. Pin the snapshot. Read and validation must use the SAME id.
        snap_id = spark.sql(f"SELECT snapshot_id FROM {TABLE}.refs "
                            "WHERE name = 'main'").first()[0]

        src = (spark.read.option("snapshot-id", snap_id).table(TABLE)
                    .where(day_filter))
        expected = src.count()                       # guard against empty/short input

        fixed = (src.withColumn("column_1", ...)     # derive all 4 columns
                    .withColumn("column_2", ...)
                    .withColumn("column_3", ...)
                    .withColumn("column_4", ...))

        if expected == 0:
            raise RuntimeError("source partition empty; refusing to overwrite")

        try:
            (fixed.writeTo(TABLE)
                  .option("isolation-level", "serializable")
                  .option("validate-from-snapshot-id", str(snap_id))
                  .option("snapshot-property.correction-id", "fix-2026-10-20-v1")
                  .overwrite(day_filter))             # or .overwritePartitions()
            return
        except Exception as e:                        # Py4J wraps ValidationException
            if "ValidationException" in str(e) and attempt < max_attempts:
                continue                              # rebuild from the NEW snapshot
            raise
```

# Identity Business-Date Partitions with Additional Partition Properties

When `business_date` is an identity partition field and the table also
partitions by other properties, one business date can span many physical
partitions. For example, `PARTITIONED BY (business_date, region,
bucket(32, customer_id))` has separate physical partitions for every
region/bucket combination within a date.

Use an explicit business-date filter with `overwrite(filter)` to replace the
entire logical date. This is safer than `overwritePartitions()` when a
subpartition can become empty: dynamic overwrite only replaces partitions
present in its output, whereas a filter can remove all pre-existing rows for
the requested date.

```python
from pyspark.sql import functions as F

TABLE = "catalog.db.fact_table"
business_date = "2026-10-15"
date_filter = F.col("business_date") == F.lit(business_date)

# Capture this immediately before reading. The source and validation baseline
# must refer to the same table snapshot.
base_snapshot_id = (
    spark.sql(f"SELECT snapshot_id FROM {TABLE}.refs WHERE name = 'main'")
         .first()[0]
)

source = (
    spark.read
         .option("snapshot-id", base_snapshot_id)
         .table(TABLE)
         .where(date_filter)
)

corrected = (
    source
    .withColumn("column_1", ...)
    .withColumn("column_2", ...)
    .withColumn("column_3", ...)
    .withColumn("column_4", ...)
)

(
    corrected.writeTo(TABLE)
    .option("isolation-level", "serializable")
    .option("validate-from-snapshot-id", str(base_snapshot_id))
    .overwrite(date_filter)
)
```

A concurrent change to a different business date can commit independently.
A change to any physical partition for `business_date = '2026-10-15'`
causes validation to fail; rebuild the whole date from the newest snapshot
before retrying. If `business_date` is not an identity partition field, use a
predicate matching the actual partition transform, such as a half-open
timestamp range for `days(event_ts)`.

Notes:

- `validate-from-snapshot-id` must be the snapshot **before the read**. If
  it is left `null`, Iceberg validates from the oldest snapshot it still
  knows about. That can flag files that were already in your input as
  "concurrent" and fail every attempt, or it validates a window you didn't
  intend.
- The filter (or the partitions in `df`) must line up with the partition
  transform. With `days(event_ts)` partitioning, use a half-open timestamp
  range on `event_ts`, not a different `event_date` column. Otherwise the
  overwrite can't drop whole files and the conflict scope gets fuzzy.
- `serializable` catches concurrent **appends and deletes** in the scope.
  `snapshot` only catches deletes, so late-arriving appends during the
  rewrite would be **lost**. Use `serializable` for corrections.
- Retrying is only safe because each attempt **re-reads**. Never re-commit
  a DataFrame built from the old snapshot.
- Iceberg-level commit retries (`commit.retry.num-retries` default 4,
  `min-wait-ms` 100, `max-wait-ms` 60000, `total-timeout-ms` 1800000) only
  handle catalog compare-and-swap races. They re-validate but never re-read
  data.
- On `CommitStateUnknownException`, **do not clean up or retry blindly**.
  The commit may have landed. Look up the `correction-id` in
  `{TABLE}.snapshots.summary` first.

# Reducing Conflicts with Ingestion

- **Serializable validation does not stay scoped to your partition when an
  operation has no usable filter.** Errors reading "matching true" mean the
  scope was the whole table, and any concurrent append conflicts. Make sure
  the overwrite filter or the UPDATE `WHERE` is a pushed-down partition
  predicate.
- Pause or time-shift the writers for the target day, or run the correction
  only for days past the late-data horizon.
- Correct days in **separate commits** (one per partition) rather than one
  giant multi-day overwrite. Each attempt is smaller and has less
  contention, and you can resume after a failure.
- Don't run compaction (`rewrite_data_files`) on the same partition at the
  same time as the correction. Compaction counts as a concurrent delete.

# Staging the Correction on a Branch (WAP)

For high-stakes corrections, write the result to a branch, audit it, then
publish it:

```sql
ALTER TABLE catalog.db.fact_table CREATE BRANCH fix_20261020 RETAIN 7 DAYS;
```

```python
fixed.writeTo("catalog.db.fact_table.branch_fix_20261020").overwritePartitions()
# audit: counts, null rates, checksums vs main
spark.sql("""SELECT count(*) FROM catalog.db.fact_table
             VERSION AS OF 'fix_20261020' WHERE event_ts >= ... AND event_ts < ...""")
```

Publish with either of:

- `CALL catalog.system.fast_forward('db.fact_table', 'main', 'fix_20261020')`.
  This **fails if `main` has moved** since the branch was created, which is
  a built-in conflict guard but impractical on a table with continuous
  ingestion.
- `CALL catalog.system.cherrypick_snapshot('db.fact_table', <branch snapshot id>)`.
  It re-applies the branch's dynamic-overwrite snapshot on top of the
  current `main`. Only append and dynamic-overwrite snapshots can be
  cherry-picked. If any data file was added to one of the replaced
  partitions on `main` since the branch point, the cherry-pick **fails**
  with `ValidationException: Cannot cherry-pick replace partitions with
  changed partition` (`CherryPickOperation.validateReplacedPartitions`)
  instead of overwriting those rows — rebuild the partition from the
  newer `main` and retry. **Correction (2026-10-22):** an earlier version
  said late appends would be silently replaced; the source shows the
  publish is validated.

See [/architecture/branching-and-tagging.md](/architecture/branching-and-tagging.md).

# Verifying the Change

```sql
-- Commit-level audit
SELECT snapshot_id, operation,
       summary['added-records']           AS added,
       summary['deleted-records']         AS deleted,
       summary['changed-partition-count'] AS parts,
       summary['correction-id']           AS correction
FROM catalog.db.fact_table.snapshots ORDER BY committed_at DESC LIMIT 5;

-- Data-level diff against the pre-correction snapshot
SELECT count(*), sum(hash(key_col)) FROM catalog.db.fact_table
  VERSION AS OF <pre_snapshot_id> WHERE event_ts >= ... AND event_ts < ...;
SELECT count(*), sum(hash(key_col)) FROM catalog.db.fact_table
  WHERE event_ts >= ... AND event_ts < ...;
```

Expected for a column-only correction: `operation = overwrite`,
`added == deleted == source row count`, `changed-partition-count` equal to
the number of days you meant to touch, and an unchanged key checksum.
Anything else points to a scope or partition-alignment bug. Roll back with
`CALL catalog.system.rollback_to_snapshot(...)` before downstream jobs read
the result.

# Throughput Tips for the Rewrite

- For a single-day rewrite, `distribution-mode=none` (write option or
  `spark.sql.iceberg.distribution-mode`) skips the pre-write shuffle. A
  practitioner bulk-load report shows a 14B-row `INSERT OVERWRITE` dropping
  from 1.3 h to 11 min. Expect more small files, so compact afterwards or
  keep `hash` if file layout matters.
- If the table has a sort order that readers rely on, keep `hash` or
  `range` distribution, or run a sort compaction afterwards.
- Size outputs with `target-file-size-bytes` and
  `spark.sql.iceberg.advisory-partition-size` (see
  [/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md)).
- Every corrected day keeps a full copy of its old files until
  `expire_snapshots` runs. Budget storage for that (500M rows/day means a
  whole extra day of data per correction).

# Citations

[1] [Apache Iceberg — Spark Configuration: write options (`isolation-level`, `validate-from-snapshot-id`)](https://iceberg.apache.org/docs/latest/spark-configuration/)
[2] [Apache Iceberg — Spark Writes (INSERT OVERWRITE, overwritePartitions, overwrite by filter, branches)](https://iceberg.apache.org/docs/latest/spark-writes/)
[3] [apache/iceberg — SparkWrite.java (DynamicOverwrite, OverwriteByFilter, CopyOnWriteOperation commit validation)](https://github.com/apache/iceberg/blob/main/spark/v3.5/spark/src/main/java/org/apache/iceberg/spark/source/SparkWrite.java)
[4] [apache/iceberg PR #2925 — Serializable and snapshot isolation for ReplacePartitions](https://github.com/apache/iceberg/pull/2925)
[5] [apache/iceberg PR #4293 — Isolation level support for DataFrame.overwrite(filter)](https://github.com/apache/iceberg/pull/4293)
[6] [SPARK-40956 — `INSERT INTO ... REPLACE WHERE` (Spark 3.4.0)](https://issues.apache.org/jira/browse/SPARK-40956)
[7] [apache/iceberg issue #12702 — REPLACE WHERE condition case sensitivity (Spark 3.5 / Iceberg 1.6)](https://github.com/apache/iceberg/issues/12702)
[8] [Ranga Reddy — Life of a write query in Iceberg (commit retry properties, ValidationException not retried) (2026)](https://rangareddy.github.io/IcebergWritePath/)
[9] [apache/iceberg issue #13091 — Concurrent MERGE on disjoint partitions still conflicts](https://github.com/apache/iceberg/issues/13091)
[10] [Expedia Group Tech — Why you should prefer MERGE INTO over INSERT OVERWRITE (partition-evolution pitfall) (2025)](https://medium.com/expedia-group-tech/why-you-should-prefer-merge-into-over-insert-overwrite-in-apache-iceberg-b6b130cc27d2)
[11] [Soumil Shah — Loading 14 billion rows into S3 Tables using INSERT OVERWRITE (distribution-mode none) (2025)](https://medium.com/@shahsoumil519/loading-6-7tb-14billion-rows-into-s3-tables-using-insert-overwrite-e95fc1d20b1b)
[12] [Apache Iceberg — Branching and Tagging (audit branch, fast_forward)](https://iceberg.apache.org/docs/latest/branching/)
[13] [gians14/iceberg-wap-incremental-pipeline — WAP reprocessing of corrupted days](https://github.com/gians14/iceberg-wap-incremental-pipeline)
[14] [apache/iceberg — CherryPickOperation.java (`validateReplacedPartitions`)](https://github.com/apache/iceberg/blob/main/core/src/main/java/org/apache/iceberg/CherryPickOperation.java)
