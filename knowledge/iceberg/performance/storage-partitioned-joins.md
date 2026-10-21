---
type: Performance Guide
title: Storage-Partitioned Joins (SPJ)
description: How Spark's storage-partitioned join uses Iceberg partition layout to join, and especially MERGE, huge tables without shuffling — requirements, Spark configs, query shape, and how to verify it in the plan.
aliases: [SPJ, storage partition join, shuffle-less join, bucketed join iceberg, v2 bucketing, preserve-data-grouping, bucket join merge into]
tags: [iceberg, performance, spark, joins, spj, merge-into, bucketing]
timestamp: 2026-10-21T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-configuration/
---

# Retrieval Notes

Read this to remove the shuffle from joins or `MERGE INTO` between two
Iceberg tables that share partitioning. For the wider MERGE tuning context
(pushdown, join hints, write distribution) see
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md).
For choosing a bucket transform see
[/performance/partitioning-strategy-for-performance.md](/performance/partitioning-strategy-for-performance.md)
and [/architecture/partition-transforms-reference.md](/architecture/partition-transforms-reference.md).

# Summary

- SPJ is the DataSource-v2 successor to Hive bucketed joins. Iceberg
  reports each scan's partitioning to Spark, and if both sides are
  compatible, Spark joins partition to partition with **no `Exchange`**.
- Available from **Spark 3.3+ with Iceberg 1.2+**. More relaxed variants
  (partially clustered, subset of keys, shuffling only one side) arrived in
  later Spark versions.
- Requirements: both sides are Iceberg tables with **compatible partition
  specs** (typically the same `bucket(N, key)`), and the join or `ON`
  condition **includes the partition columns**.
- Strongest use case: `MERGE INTO` a huge target from a staging table that
  has the same partition spec. Only the matching buckets are joined, and
  the target is never reshuffled.

# Spark Configuration

```properties
# core SPJ switches
spark.sql.sources.v2.bucketing.enabled=true
spark.sql.sources.v2.bucketing.pushPartValues.enabled=true
spark.sql.iceberg.planning.preserve-data-grouping=true
spark.sql.requireAllClusterKeysForCoPartition=false
# handle skew: split big partitions on one side, replicate the other
spark.sql.sources.v2.bucketing.partiallyClusteredDistribution.enabled=true
# avoid re-sorting each bucket (see the shuffle-hash note below)
spark.sql.join.preferSortMergeJoin=false
# newer Spark: shuffle only the smaller side to match the larger side's layout
spark.sql.sources.v2.bucketing.shuffle.enabled=true
```

`spark.sql.iceberg.planning.preserve-data-grouping` is the Iceberg-side
switch. It keeps scan tasks of the same partition in the same split, so
Spark can see the grouping. Some configs (`bucketing.shuffle.enabled`,
`allowJoinKeysSubsetOfPartitionKeys`) only exist in newer Spark releases.
Check your Spark version's SQL config list.

# Query Shape for MERGE

```sql
-- Target and staging are both PARTITIONED BY (days(ts), bucket(256, id))
MERGE INTO prod.db.events t
USING prod.db.events_staging s
ON  t.id = s.id
AND days(t.ts) = days(s.ts)      -- or join on the partition source column(s)
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
```

- Put the partition columns in `ON`. Without them Spark can't prove the
  two sides are co-partitioned.
- The staging table must be an **Iceberg table** with the same spec. A
  temp view over a plain DataFrame has no reported partitioning. Writing the
  batch to an Iceberg staging table first (optionally through WAP) is the
  usual pattern, used by Ancestry.
- If the staging side can't be pre-partitioned, newer Spark versions with
  `v2.bucketing.shuffle.enabled=true` will shuffle *only the small side*
  to match the target's buckets. ZeroToOne cut a 2-billion-row merge from
  about 60 to about 40 minutes this way, then to about 4 minutes by adding
  a `SHUFFLE_HASH` join hint.

# Verifying It Worked

- In `EXPLAIN FORMATTED` / the Spark UI SQL tab, the join's children should
  be `BatchScan`s with **no `Exchange`** above them. A `Sort` above each
  side means sort-merge join is still in use. Add `preferSortMergeJoin=false`
  and a `SHUFFLE_HASH` hint.
- GitHub issue apache/iceberg#7832 is a common trap: the configs were set,
  but the merge still did a full shuffled batch scan, because the partition
  columns weren't in the join condition or the specs didn't match.

# Caveats

- Bucket counts must be compatible. The same N is simplest. Partition-spec
  evolution on one side breaks SPJ until old data is rewritten.
- Badly skewed buckets need
  `partiallyClusteredDistribution.enabled`, or a higher bucket count.
- AQE can re-plan the join at runtime. If the plan changes between runs,
  compare plans with AQE on and off for that job.

# Citations

[1] [Apache Iceberg — Spark Configuration (`spark.sql.iceberg.planning.preserve-data-grouping`)](https://iceberg.apache.org/docs/latest/spark-configuration/)
[2] [Expedia Group Tech — Mastering Spark-Iceberg joins with Storage-Partitioned Join (2024)](https://medium.com/expedia-group-tech/turbocharge-efficiency-slash-costs-mastering-spark-iceberg-joins-with-storage-partitioned-join-03fdc1ff75c0)
[3] [Akashdeep Gupta — Optimizing Iceberg MERGE Statements (2025)](https://www.guptaakashdeep.com/optimizing-iceberg-merge-statements/)
[4] [ZeroToOne — From 60 Minutes to 4: Optimizing Spark MERGE INTO on a 2 Billion Row Iceberg Table (2026)](https://blog.platform.zerotoone.ai/blog/spark-merge-optimization-from-60-to-4-minutes/)
[5] [AWS Big Data Blog — How Ancestry optimizes a 100-billion-row Iceberg table (2025)](https://aws.amazon.com/blogs/big-data/how-ancestry-optimizes-a-100-billion-row-iceberg-table/)
[6] [apache/iceberg issue #7832 — Implementing Storage Partition join and reducing the time for MERGE](https://github.com/apache/iceberg/issues/7832)
