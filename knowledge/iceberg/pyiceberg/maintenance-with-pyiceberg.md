---
type: PyIceberg Guide
title: PyIceberg — Table Maintenance (Snapshot Expiration and Snapshot Management)
description: Maintenance operations available from PyIceberg's Python API — expiring snapshots, managing branches/tags, and rollback — plus what is NOT yet available (compaction) compared to Spark.
aliases: [pyiceberg expire_snapshots, pyiceberg maintenance, pyiceberg compaction, pyiceberg rewrite_data_files, table.maintenance, MaintenanceTable, ExpireSnapshots, ManageSnapshots]
tags: [pyiceberg, python, maintenance, snapshots, expire-snapshots, compaction]
timestamp: 2026-07-31T00:00:00Z
resource: https://py.iceberg.apache.org/reference/pyiceberg/table/maintenance
---

# Retrieval Notes

Read this first for "how do I expire snapshots in PyIceberg", "does PyIceberg
support compaction / rewrite_data_files", or "PyIceberg branch/tag/rollback API".
For the conceptual *why* of snapshot expiration and table maintenance in general
(retention policy, orphan files, compaction rationale), see
`/maintenance/expire-snapshots.md` and other `/maintenance/` concepts in this
bundle — those cover the Spark/Java maintenance actions this concept does not
duplicate. For writes that create the snapshots being managed, see
[writing-and-upsert.md](writing-and-upsert.md).

# Summary

- **Compaction / `rewrite_data_files` is NOT available in PyIceberg** as of this
  documentation snapshot — the fast-append write strategy PyIceberg uses by
  default produces more, smaller metadata/data artifacts than Java's merge
  commits, and compaction to consolidate them is tracked as a planned feature
  upstream, not yet shipped. Do not assume feature parity with the Spark
  maintenance actions (`rewrite_data_files`, `rewrite_manifests`, etc.) covered
  elsewhere in this knowledge base — for those, use PySpark.
- What PyIceberg **does** provide from Python: `table.maintenance.expire_snapshots()`
  (an `ExpireSnapshots` builder) and `table.manage_snapshots()` (a
  `ManageSnapshots` builder for tags, branches, and rollback).
- `expire_snapshots()` can target snapshots `.by_id(id)`, `.by_ids([...])`, or
  `.older_than(datetime)`; branch/tag **HEAD snapshots are always protected**
  from expiration automatically.
- `manage_snapshots()` covers `create_tag`, `remove_tag`, `create_branch`,
  `remove_branch`, `set_current_snapshot`, `rollback_to_snapshot`, and
  `rollback_to_timestamp`.
- Both builders support method chaining and `.commit()`, or a `with ... as x:`
  context-manager form that auto-commits on exit.

# What's Available vs. Not (vs. Spark/Java)

| Operation | PyIceberg | Spark/Java Iceberg |
|---|---|---|
| Expire snapshots | Yes — `table.maintenance.expire_snapshots()` | Yes — `expire_snapshots` procedure |
| Create/remove branch or tag | Yes — `table.manage_snapshots()` | Yes |
| Rollback to snapshot/timestamp | Yes — `table.manage_snapshots()` | Yes |
| Set current snapshot | Yes — `set_current_snapshot()` | Yes |
| **Compact data files (`rewrite_data_files`)** | **No** (planned, not shipped) | Yes |
| Rewrite manifests | Not exposed as a maintenance builder | Yes |
| Remove orphan files | Not exposed as a maintenance builder | Yes |

If you need compaction or orphan-file cleanup today, run those actions from
Spark against the same Iceberg table/catalog rather than PyIceberg.

# Snapshot Expiration

```python
from datetime import datetime, timedelta

# Expire snapshots older than three days
table.maintenance.expire_snapshots().older_than(
    datetime.now() - timedelta(days=3)
).commit()

# Expire a specific snapshot by ID
table.maintenance.expire_snapshots().by_id(12345).commit()

# Context manager usage (recommended for multiple operations)
with table.maintenance.expire_snapshots() as expire:
    expire.by_id(12345)
    expire.by_id(67890)
    # Automatically commits when exiting the context
```

## `ExpireSnapshots` builder methods

| Method | Signature | Behavior |
|---|---|---|
| `by_id` | `by_id(snapshot_id: int) -> ExpireSnapshots` | Marks one snapshot for expiration; raises `ValueError` if the snapshot doesn't exist or is protected (a branch/tag HEAD) |
| `by_ids` | `by_ids(snapshot_ids: list[int]) -> ExpireSnapshots` | Calls `by_id` for each ID in the list |
| `older_than` | `older_than(dt: datetime) -> ExpireSnapshots` | Marks all **unprotected** snapshots with `timestamp < dt` for expiration |

Protected snapshots — the HEAD of any branch or tag — are automatically excluded
from expiration even if matched by `older_than`, and `.by_id()` raises if you try
to expire one explicitly.

## Real-world example

```python
def cleanup_old_snapshots(table_name: str, snapshot_ids: list[int]):
    """Remove specific snapshots from a table."""
    catalog = load_catalog("production")
    table = catalog.load_table(table_name)

    with table.maintenance.expire_snapshots() as expire:
        for snapshot_id in snapshot_ids:
            expire.by_id(snapshot_id)

    print(f"Expired {len(snapshot_ids)} snapshots from {table_name}")

cleanup_old_snapshots("analytics.user_events", [12345, 67890, 11111])
```

# Snapshot Management (branches, tags, rollback)

`table.manage_snapshots()` returns a `ManageSnapshots` builder:

```python
# Single operation
table.manage_snapshots().create_tag(snapshot_id, "tag123").commit()

# Multiple operations
table.manage_snapshots() \
    .create_tag(snapshot_id1, "tag123") \
    .create_tag(snapshot_id2, "tag456") \
    .commit()

# Context manager
with table.manage_snapshots() as ms:
    ms.create_branch(snapshot_id1, "Branch_A").create_tag(snapshot_id2, "tag789")
```

## Tags

Tags are immutable named references to a snapshot — good for marking releases or
long-term-retained versions.

```python
table.manage_snapshots().create_tag(
    snapshot_id=snapshot_id,
    tag_name="v1.0.0"
).commit()

# With a custom retention window
table.manage_snapshots().create_tag(
    snapshot_id=snapshot_id,
    tag_name="v1.0.0",
    max_ref_age_ms=604800000  # 7 days
).commit()

table.manage_snapshots().remove_tag("v1.0.0").commit()
```

`create_tag(snapshot_id, tag_name, max_ref_age_ms=None)`.

## Branches

Branches are mutable named references — useful for dev/test lineages that
diverge from `main`.

```python
table.manage_snapshots().create_branch(
    snapshot_id=snapshot_id,
    branch_name="dev"
).commit()

table.manage_snapshots().create_branch(
    snapshot_id=snapshot_id,
    branch_name="dev",
    max_ref_age_ms=604800000,        # max age of the branch ref itself (7 days)
    max_snapshot_age_ms=259200000,   # max age of snapshots kept on the branch (3 days)
    min_snapshots_to_keep=10         # floor on retained snapshots regardless of age
).commit()

table.manage_snapshots().remove_branch("dev").commit()
```

`create_branch(snapshot_id, branch_name, max_ref_age_ms=None, max_snapshot_age_ms=None, min_snapshots_to_keep=None)`.

## Set current snapshot / rollback

| Method | Signature | Behavior |
|---|---|---|
| `set_current_snapshot` | `set_current_snapshot(snapshot_id=None, ref_name=None)` | Points `main` at a specific snapshot ID or an existing ref; exactly one of the two args must be given |
| `rollback_to_snapshot` | `rollback_to_snapshot(snapshot_id: int)` | Rolls `main` back to `snapshot_id`; the snapshot must be an ancestor of the current state, else raises `ValueError` |
| `rollback_to_timestamp` | `rollback_to_timestamp(timestamp_ms: int)` | Rolls `main` back to the latest ancestor snapshot before `timestamp_ms` |

```python
table.manage_snapshots().rollback_to_snapshot(snapshot_id).commit()
table.manage_snapshots().rollback_to_timestamp(timestamp_ms).commit()
```

# Citations

[1] [PyIceberg — Python API: Table Maintenance](https://py.iceberg.apache.org/api#table-maintenance)
[2] [PyIceberg reference — `maintenance` module](https://py.iceberg.apache.org/reference/pyiceberg/table/maintenance)
[3] [PyIceberg reference — `table/update/snapshot` module](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot)
