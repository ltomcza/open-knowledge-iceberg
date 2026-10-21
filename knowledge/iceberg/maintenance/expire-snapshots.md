---
type: Maintenance Guide
title: Expire Snapshots
description: Why Iceberg snapshots must be expired regularly, retention settings, and how expiration interacts with time travel, branches, and tags.
aliases: [expire_snapshots, snapshot expiration, snapshot retention, history.expire, time travel cleanup, GC snapshots]
tags: [iceberg, maintenance, snapshots, garbage-collection, time-travel]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/maintenance/
---

# Retrieval Notes

Read this when storage/metadata is growing unexpectedly, or when planning
retention policy for time travel and branches/tags. For the exact `CALL`
syntax and every argument, see
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) (procedure:
`expire_snapshots`). For deleting files left behind by failed jobs rather
than expired snapshots, see
[/maintenance/remove-orphan-files.md](/maintenance/remove-orphan-files.md).
For overall pipeline ordering, see
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md).

# Summary

- Every write/update/delete/upsert/compaction creates a new **snapshot**;
  old snapshots (and the data files uniquely referenced by them) accumulate
  indefinitely unless expired.
- Expiring snapshots is what actually reclaims storage — data files are
  never deleted while any live snapshot still requires them, only once the
  last referencing snapshot expires.
- Expiration also keeps table **metadata** small (fewer entries in the
  snapshot history embedded in the metadata JSON).
- Retention is controlled by `older_than` (default 5 days ago) and
  `retain_last` (default: keep at least 1 snapshot), or the table's
  `history.expire.*` properties if arguments are omitted.
- Snapshots still referenced by a **branch or tag are never removed**,
  regardless of age — branches/tags have their own independent max-age
  property, and `main` never expires.
- Expiring a snapshot removes it from time-travel history — queries
  targeting an expired `snapshot-id` or `as-of-timestamp` before it will
  fail.

# Why Expiration Matters

- **Storage growth** — data files referenced only by old snapshots are
  "invisible" to current reads but still occupy storage until their
  snapshot is expired and garbage-collected.
- **Metadata bloat** — the table metadata JSON tracks snapshot history;
  unbounded snapshot accumulation grows this file and slows metadata
  operations.
- Note that `expireSnapshots`/`expire_snapshots` never deletes a file that
  a still-live snapshot needs — it is safe with respect to any snapshot you
  haven't expired.

# Retention Settings

| Setting | Where | Default | Effect |
|---|---|---|---|
| `older_than` | procedure arg | 5 days ago | Snapshots older than this are candidates for removal |
| `retain_last` | procedure arg | 1 | Minimum number of most-recent snapshots kept regardless of age |
| `history.expire.max-snapshot-age-ms` | table property | 432000000 (5 days) | Default max age used when `older_than` isn't passed |
| `history.expire.min-snapshots-to-keep` | table property | 1 | Default min-keep used when `retain_last` isn't passed |
| `history.expire.max-ref-age-ms` | table property | `Long.MAX_VALUE` (forever) | Max age for snapshot **references** (branches/tags) other than `main`; `main` never expires |
| `gc.enabled` | table property | true | Master switch — must be true for expiration/orphan-removal to run at all |

If `older_than`/`retain_last` are omitted from the procedure call, the
table's `history.expire.*` properties apply.

```sql
-- remove snapshots older than a date, but always keep the last 100
CALL hive_prod.system.expire_snapshots('db.sample', TIMESTAMP '2021-06-30 00:00:00.000', 100);

-- remove specific snapshot IDs directly (must not be the current snapshot)
CALL hive_prod.system.expire_snapshots(table => 'db.sample', snapshot_ids => ARRAY(123));
```

Full argument reference (including `clean_expired_metadata`,
`max_concurrent_deletes`, `stream_results`) is in
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md).

# Interaction with Time Travel

Time travel and rollback both work by reading the table as of a past
snapshot. Expiring a snapshot permanently removes that option for it:

- Queries with `snapshot-id` or `as-of-timestamp` pointing at an expired
  snapshot will fail once the snapshot (and its uniquely-owned files) is
  gone.
- Set retention long enough to cover your organization's time-travel /
  audit / debugging window before tightening it for storage cost reasons —
  this is a direct tradeoff between storage cost and travel-back depth.

# Interaction with Branches and Tags

- A snapshot referenced by a **branch** or **tag** is protected from
  expiration even if it is older than `older_than` — expiration only
  removes snapshots with no remaining reference.
- Branches and tags default to **never** expiring their own reference; set
  `history.expire.max-ref-age-ms` (or a per-ref override, if your engine
  exposes one) to bound how long a tag/branch — and therefore the storage
  it pins — stays alive.
- `main` is a special branch that **never** expires as a reference,
  regardless of `max-ref-age-ms`.
- Practical implication: long-lived tags (e.g. "end of quarter" snapshots
  kept for audit) will pin their underlying data files indefinitely — budget
  storage accordingly, and clean up tags you no longer need before running
  expiration to reclaim their files.

# Citations

[1] [Apache Iceberg — Maintenance: Expire Snapshots](https://iceberg.apache.org/docs/latest/maintenance/#expire-snapshots)
[2] [Apache Iceberg — Spark Procedures: expire_snapshots](https://iceberg.apache.org/docs/latest/spark-procedures/#expire_snapshots)
[3] [Apache Iceberg — Configuration: table behavior properties](https://iceberg.apache.org/docs/latest/configuration/#table-behavior-properties)
