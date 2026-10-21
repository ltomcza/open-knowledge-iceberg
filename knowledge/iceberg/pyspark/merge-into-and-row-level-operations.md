---
type: PySpark Guide
title: MERGE INTO, UPDATE, and DELETE — Row-Level Operations in PySpark
description: MERGE INTO (SQL and DataFrame mergeInto) matched/not-matched/not-matched-by-source clauses, UPDATE, DELETE FROM, snapshot summary fields, and upsert/CDC patterns and pitfalls for Iceberg tables in PySpark.
aliases: [iceberg merge into pyspark, upsert iceberg spark, WHEN MATCHED THEN UPDATE, WHEN NOT MATCHED THEN INSERT, DataFrame mergeInto, delete from iceberg spark, update iceberg spark, cdc iceberg spark]
tags: [iceberg, pyspark, spark, merge-into, upsert, cdc, update, delete]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-writes
---

# Retrieval Notes

Read this for row-level upserts, updates, and deletes against Iceberg
tables — `MERGE INTO`, `UPDATE`, `DELETE FROM`, and their DataFrame
(`mergeInto`) equivalent. For plain appends/overwrites/CTAS see
`/pyspark/writing-data.md`. For read-side upsert/CDC prerequisites
(identifier fields) see `/pyspark/ddl-create-alter-tables.md#identifier-fields`.
For copy-on-write vs merge-on-read table modes affecting UPDATE/DELETE/MERGE
cost, see `/architecture/` (row-level-operation-modes, owned elsewhere in
this bundle) — table properties `write.update.mode`,
`write.delete.mode`, `write.merge.mode` (`copy-on-write` default,
`merge-on-read` available) control this and are set via `ALTER TABLE ...
SET TBLPROPERTIES`.

# Summary

- `MERGE INTO` is Iceberg's recommended way to do row-level upserts: it
  rewrites only the affected data files (an `overwrite` commit), and unlike
  `INSERT OVERWRITE` its behavior does not silently change when the
  table's partition spec evolves.
- `WHEN MATCHED` clauses run in order — the **first matching** expression
  wins. Only one source row may match any given target row, or Spark
  throws an error at runtime (fan-out joins are not allowed on the matched
  side).
- `WHEN NOT MATCHED THEN INSERT *` inserts unmatched source rows;
  `WHEN NOT MATCHED BY SOURCE` (Spark 3.5+) updates/deletes target rows
  that have **no** corresponding source row — useful for full-state sync /
  hard-delete propagation.
- `DELETE FROM` is metadata-only (fast) when the filter aligns to whole
  partitions; it falls back to rewriting affected data files when the
  filter matches individual rows within files.
- `MERGE INTO`, `UPDATE`, and `DELETE FROM` all require Iceberg SQL
  extensions (`IcebergSparkSessionExtensions`) — see
  `/pyspark/setup-and-configuration.md`.
- The DataFrame equivalent, `DataFrame.mergeInto(table, condition)` →
  `MergeIntoWriter`, was added in **Spark 4.0**; chain
  `.whenMatched(...)`, `.whenNotMatched(...)`,
  `.whenNotMatchedBySource(...)` with `.update(...)`/`.updateAll()`/
  `.insert(...)`/`.insertAll()`/`.delete()`, then call `.merge()`.
- Since Spark 4.1, a successful `MERGE INTO` commit's snapshot summary can
  report exact counts (`spark.merge-into.num-target-rows-*`) — useful for
  auditing/alerting on unexpectedly large upserts.

# MERGE INTO (SQL)

`MERGE INTO` updates a **target** table using rows from a **source**
query, matched via an `ON` condition (like a join key):

```python
spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.data = s.data
WHEN NOT MATCHED THEN INSERT *
""")
```

## Matched clauses (first match wins)

```python
spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s
ON t.id = s.id
WHEN MATCHED AND s.op = 'delete' THEN DELETE
WHEN MATCHED AND t.count IS NULL AND s.op = 'increment' THEN UPDATE SET t.count = 0
WHEN MATCHED AND s.op = 'increment' THEN UPDATE SET t.count = t.count + 1
""")
```

## Not-matched (insert) clause, with optional condition

```python
spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT *
""")

spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s
ON t.id = s.id
WHEN NOT MATCHED AND s.event_time > still_valid_threshold THEN INSERT (id, count) VALUES (s.id, 1)
""")
```

> Only one source row may match a given target row — a second match for
> the same target row throws an error.

## Not matched by source (Spark 3.5+)

Updates or deletes target rows that have no matching source row at all —
e.g. to hard-delete rows absent from a full snapshot feed:

```python
spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s
ON t.id = s.id
WHEN NOT MATCHED BY SOURCE THEN UPDATE SET status = 'invalid'
""")
```

## MERGE INTO on a branch

```python
spark.sql("""
MERGE INTO prod.db.table.branch_audit t
USING (SELECT ...) s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.data = s.data
WHEN NOT MATCHED THEN INSERT *
""")
```

## Snapshot summary fields (Spark 4.1+)

After a successful commit, these string-count fields may appear in the
snapshot summary (omitted if Spark doesn't report a value):

| Field | Meaning |
|---|---|
| `spark.merge-into.num-target-rows-copied` | Target rows copied unmodified (matched no action) |
| `spark.merge-into.num-target-rows-deleted` | Total target rows deleted |
| `spark.merge-into.num-target-rows-updated` | Total target rows updated |
| `spark.merge-into.num-target-rows-inserted` | Total target rows inserted |
| `spark.merge-into.num-target-rows-matched-updated` | Rows updated by a `MATCHED` clause |
| `spark.merge-into.num-target-rows-matched-deleted` | Rows deleted by a `MATCHED` clause |
| `spark.merge-into.num-target-rows-not-matched-by-source-updated` | Rows updated by `NOT MATCHED BY SOURCE` |
| `spark.merge-into.num-target-rows-not-matched-by-source-deleted` | Rows deleted by `NOT MATCHED BY SOURCE` |

Inspect via `SELECT * FROM prod.db.target.snapshots` — see
`/pyspark/reading-data-and-queries.md`.

# UPDATE (SQL)

```python
spark.sql("""
UPDATE prod.db.table
SET c1 = 'update_c1', c2 = 'update_c2'
WHERE ts >= '2020-05-01 00:00:00' and ts < '2020-06-01 00:00:00'
""")

spark.sql("""
UPDATE prod.db.all_events
SET session_time = 0, ignored = true
WHERE session_time < (SELECT min(session_time) FROM prod.db.good_events)
""")

spark.sql("""
UPDATE prod.db.orders AS t1
SET order_status = 'returned'
WHERE EXISTS (SELECT oid FROM prod.db.returned_orders WHERE t1.oid = oid)
""")

# on a branch
spark.sql("""
UPDATE prod.db.table.branch_audit AS t1
SET val = 'c'
""")
```

For more complex row-level updates driven by another dataset, prefer
`MERGE INTO` over `UPDATE`.

# DELETE FROM (SQL)

```python
spark.sql("""
DELETE FROM prod.db.table
WHERE ts >= '2020-05-01 00:00:00' and ts < '2020-06-01 00:00:00'
""")

spark.sql("""
DELETE FROM prod.db.all_events
WHERE session_time < (SELECT min(session_time) FROM prod.db.good_events)
""")

spark.sql("""
DELETE FROM prod.db.orders AS t1
WHERE EXISTS (SELECT oid FROM prod.db.returned_orders WHERE t1.oid = oid)
""")

# on a branch
spark.sql("DELETE FROM prod.db.table.branch_audit WHERE id = 2")
```

If the filter matches whole partitions, Iceberg performs a **metadata-only
delete** (no data rewrite). If it matches individual rows within files,
Iceberg rewrites just the affected data files (or writes delete files
under merge-on-read).

# MERGE INTO via DataFrame (Spark 4.0+)

`DataFrame.mergeInto(table, condition) -> MergeIntoWriter`. `condition`
determines whether a source row matches a target row.

```python
from pyspark.sql.functions import expr, lit

source = spark.table("updates")  # or any DataFrame of incoming changes

(source.mergeInto("target", source["id"] == expr("target.id"))
    .whenMatched(source["id"] == 1)
    .update({"name": source["name"]})
    .whenMatched(source["id"] == 2)
    .delete()
    .whenNotMatched()
    .insertAll()
    .whenNotMatchedBySource(expr("target.id") == 3)
    .update({"status": lit("invalid")})
    .merge())
```

Simpler full-upsert-plus-hard-delete pattern straight from the PySpark
docs:

```python
from pyspark.sql.functions import expr

source = spark.createDataFrame(
    [(14, "Tom"), (23, "Alice"), (16, "Bob")], ["id", "name"])

(source.mergeInto("target", "id")
    .whenMatched().update({"name": source["name"]})
    .whenNotMatched().insertAll()
    .whenNotMatchedBySource().delete()
    .merge())
```

`MergeIntoWriter` method shapes seen above:

| Method | Purpose |
|---|---|
| `.whenMatched(condition=None)` | Start a matched clause, optionally scoped by an extra condition |
| `.whenNotMatched(condition=None)` | Start a not-matched (insert) clause |
| `.whenNotMatchedBySource(condition=None)` | Start a clause for target rows absent from source |
| `.update(dict)` | Update named columns to given expressions |
| `.updateAll()` | Update all columns from the matching source row |
| `.insert(dict)` | Insert specific columns |
| `.insertAll()` | Insert all columns from the source row |
| `.delete()` | Delete the row |
| `.merge()` | Execute the merge |

> `mergeInto` does not support streaming queries.

# Common Upsert / CDC Pitfalls

- **Copy-on-write vs merge-on-read**: by default `write.update.mode`,
  `write.delete.mode`, and `write.merge.mode` are `copy-on-write` — every
  `UPDATE`/`DELETE`/`MERGE` rewrites whole affected data files, which is
  simple but can be expensive against wide, infrequently-compacted tables.
  Switching those table properties to `merge-on-read` writes lightweight
  delete files instead and defers the rewrite to compaction — cheaper
  writes, more expensive reads until compacted. Set per-table via
  `ALTER TABLE ... SET TBLPROPERTIES ('write.merge.mode'='merge-on-read')`
  (and the update/delete equivalents).
- **One source row per target row**: a `MERGE INTO` whose `ON` condition
  fans out (multiple source rows matching one target row) fails at
  runtime — dedupe the source (e.g. `ROW_NUMBER()` / `first()` /
  `groupBy`) before merging, especially for CDC streams with multiple
  events per key in a batch.
- **Merge-on-read tables need regular compaction**: frequent small
  upserts against a merge-on-read table accumulate delete files quickly,
  degrading read performance — schedule `rewrite_data_files` /
  `rewrite_position_delete_files`; see
  `/maintenance/compaction-and-file-sizing.md` and
  `/pyspark/spark-procedures.md`.
- **Identifier fields help downstream engines**: setting
  `SET IDENTIFIER FIELDS` (see
  `/pyspark/ddl-create-alter-tables.md#identifier-fields`) is required for
  some engines' upsert modes (e.g. Flink SQL) reading the same table, even
  though plain Spark `MERGE INTO` doesn't require it.
- **`WHEN NOT MATCHED BY SOURCE` vs a separate `DELETE`**: for full-state
  CDC sync (drop rows no longer present upstream), prefer a single
  `MERGE INTO ... WHEN NOT MATCHED BY SOURCE THEN DELETE` over an
  unconditional `INSERT OVERWRITE` — it only rewrites affected files and
  is unaffected by partition-spec evolution, unlike dynamic
  `INSERT OVERWRITE` (see `/pyspark/writing-data.md`).

# Performance at Scale

For making MERGE fast on billion-row tables (ON-clause pushdown, bounded
merges, SPJ, shuffle-hash joins, distribution modes) see
[/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md)
and [/performance/storage-partitioned-joins.md](/performance/storage-partitioned-joins.md).

# Citations

[1] [Spark Writes](https://iceberg.apache.org/docs/latest/spark-writes)
[2] [pyspark.sql.DataFrame.mergeInto](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrame.mergeInto.html)
