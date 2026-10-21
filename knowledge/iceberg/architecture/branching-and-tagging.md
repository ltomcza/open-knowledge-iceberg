---
type: Iceberg Concept
title: Branching and Tagging
description: Iceberg branches vs. tags as named snapshot references, the write-audit-publish (WAP) pattern, and branch/tag retention properties.
aliases: [iceberg branches, iceberg tags, write-audit-publish, WAP pattern, snapshot references, fast-forward, tag retention, branch retention]
tags: [iceberg, architecture, branching, tagging, snapshots, retention]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/branching
---

# Retrieval Notes

Read this for named references to snapshots and workflow patterns built on
them. For the underlying snapshot mechanics being referenced, see
[snapshots-and-versioning.md](snapshots-and-versioning.md). For general
snapshot expiration/retention concepts, this is also where retention
properties for branches/tags specifically live (as opposed to the table's
overall history retention).

# Summary

- **Branches** and **tags** are named **snapshot references**, each with its
  own independent lifecycle and retention policy, stored in the table
  metadata `refs` map.
- A **tag** is a fixed label on a single snapshot — it never moves.
- A **branch** is a mutable, independent lineage of snapshots — its pointer
  moves forward as new snapshots are committed to it, just like `main`.
- Every table always has a `main` branch (even if `refs` is absent/empty,
  `main` implicitly points at `current-snapshot-id`); `main` never expires.
- **Write-Audit-Publish (WAP)**: write to an isolated branch, validate
  (audit) the data there, then **fast-forward** `main` to that branch's
  head once validated — production readers never see unvalidated data.
- Retention properties (`min-snapshots-to-keep`, `max-snapshot-age-ms` for
  branches; `max-ref-age-ms` for the reference itself) let you keep, e.g.,
  weekly/monthly/yearly audit tags cheaply without retaining the full daily
  snapshot history.
- **Schema note**: querying the head of a branch uses the **table's
  current schema**; querying via a tag or a specific historical snapshot ID
  uses **that snapshot's schema** at creation time.

# Branches vs. Tags

| | Tag | Branch |
|---|---|---|
| Points to | One fixed snapshot | The head of an independent, growing lineage |
| Moves over time? | No | Yes — advances as new snapshots are committed to it |
| Typical use | Retain a historical point for audit/compliance/reproducibility | Isolate in-progress writes (WAP), long-lived experimental branches |
| Default retention | Forever unless configured | Forever unless configured; also has `min-snapshots-to-keep` / `max-snapshot-age-ms` for its own history |

# Snapshot Reference Fields

| Field | Type | Description |
|---|---|---|
| `snapshot-id` | long | The tagged snapshot, or the branch's current head. |
| `type` | string | `tag` or `branch`. |
| `min-snapshots-to-keep` | int | Branch-only: minimum snapshots to retain on the branch during expiration. |
| `max-snapshot-age-ms` | long | Branch-only: max age of snapshots to retain, including the head. |
| `max-ref-age-ms` | long | Any ref except `main`: max age of the reference itself before it's removed. `main` never expires. |

# Use Cases

**Historical tags for auditing** — retain a rolling set of point-in-time
snapshots cheaply:

```sql
-- Weekly tag, retained 7 days
ALTER TABLE prod.db.table CREATE TAG `EOW-01` AS OF VERSION 7 RETAIN 7 DAYS;

-- Monthly tag, retained 6 months
ALTER TABLE prod.db.table CREATE TAG `EOM-01` AS OF VERSION 30 RETAIN 180 DAYS;

-- Yearly tag, retained forever (default)
ALTER TABLE prod.db.table CREATE TAG `EOY-2023` AS OF VERSION 365;
```

**Temporary experimental branch**, auto-expiring:

```sql
ALTER TABLE prod.db.table CREATE BRANCH `test-branch`
  RETAIN 7 DAYS WITH SNAPSHOT RETENTION 2 SNAPSHOTS;
```

# Write-Audit-Publish (WAP) Pattern

1. Enable WAP on the table:
   ```sql
   ALTER TABLE db.table SET TBLPROPERTIES ('write.wap.enabled'='true');
   ```
2. Create an isolated audit branch from a known-good snapshot:
   ```sql
   ALTER TABLE db.table CREATE BRANCH `audit-branch` AS OF VERSION 3 RETAIN 7 DAYS;
   ```
3. Write to the branch only (production `main` is untouched):
   ```sql
   SET spark.wap.branch = audit-branch;
   INSERT INTO prod.db.table VALUES (3, 'c');
   ```
4. Run a validation/data-quality workflow against `audit-branch`.
5. On success, fast-forward `main` to publish the validated state:
   ```sql
   CALL catalog_name.system.fast_forward('prod.db.table', 'main', 'audit-branch');
   ```
6. The now-unneeded branch reference is removed automatically once
   `expireSnapshots` runs past its `RETAIN` window.

# Schema Selection with Branches and Tags

- **Writing to a branch** and **reading the branch head** both use the
  table's **current schema** (the branch shares the table's live schema —
  it is not schema-isolated).
- **Reading via a tag**, or via `VERSION AS OF <snapshot-id>` for a specific
  historical snapshot, uses the **schema-id recorded on that snapshot** at
  the time it was created — so old tags/time-travel queries see the schema
  as it was then, even if the table's schema has since evolved.

# Usage Surfaces

Branches/tags are supported in the Iceberg Java library and in Spark and
Flink integrations (DDL, reads, and writes) — consult the engine-specific
docs (e.g. `/pyspark/`, `/flink/` concepts) for exact syntax.

# Citations

[1] [Apache Iceberg Documentation — Branching and Tagging](https://iceberg.apache.org/docs/latest/branching)
[2] [Apache Iceberg Table Spec — Snapshot References](https://iceberg.apache.org/spec)
[3] [Apache Iceberg Table Spec — Snapshot Retention Policy](https://iceberg.apache.org/spec)
