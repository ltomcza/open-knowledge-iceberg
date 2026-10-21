---
type: Iceberg Concept
title: Snapshots and Versioning
description: Structure of an Iceberg snapshot, the snapshot log, parent-child snapshot lineage, and how a single write produces a new snapshot atomically.
aliases: [iceberg snapshot, snapshot lineage, snapshot log, time travel, version rollback, current-snapshot-id, snapshot summary]
tags: [iceberg, architecture, snapshots, versioning, time-travel, reliability]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/spec
---

# Retrieval Notes

Read this for what a snapshot *is* and how snapshot history works. For the
files a snapshot points to, see [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md).
For the concurrency/commit protocol that produces new snapshots, see
[reliability-and-concurrency.md](reliability-and-concurrency.md). For named,
independently-retained references to snapshots, see
[branching-and-tagging.md](branching-and-tagging.md).

# Summary

- A **snapshot** is the complete state of a table's data at one point in
  time — the set of all data files (and delete files) visible then. Every
  write or delete produces a **new** snapshot.
- Snapshots form a **linear (or branching) lineage** via `parent-snapshot-id`
  — each snapshot points to the snapshot it was built from, except the
  first, which has no parent.
- A write is made durable and visible **atomically**: a snapshot only
  "exists" from a reader's perspective once `current-snapshot-id` in a
  successfully-committed `metadata.json` points to it. There is no partial
  visibility.
- The **snapshot log** (`snapshot-log` in table metadata) is the ordered
  history of `{timestamp, snapshot-id}` pairs recording every change to
  which snapshot is current — this plus retained old snapshots is what
  powers time travel and rollback.
- A snapshot's `summary.operation` field (`append`, `replace`, `overwrite`,
  `delete`) tells consumers what kind of change produced it, and is used by
  operations like snapshot expiration to decide what to keep.
- Snapshots reference a **manifest list**, not manifests directly — manifest
  files themselves are frequently reused unchanged across snapshots.

# Snapshot Fields

| Field | Requirement | Description |
|---|---|---|
| `snapshot-id` | required | Unique long ID. |
| `parent-snapshot-id` | optional | ID of the parent snapshot; omitted if this is the first snapshot. |
| `sequence-number` | required (v2+) | Monotonically increasing long tracking change order. |
| `timestamp-ms` | required | Creation time, used for GC and inspection. |
| `manifest-list` | required (v2+) | Location of this snapshot's manifest list file. |
| `summary` | required | String map summarizing the change; must include `operation`. |
| `schema-id` | optional | The table's current schema ID at the time this snapshot was created. |
| `first-row-id` / `added-rows` | required (v3+) | Row-lineage bookkeeping — first assigned `_row_id` and upper bound of rows with assigned IDs. |
| `key-id` | optional (v3+) | ID of the encryption key protecting the manifest list's key metadata. |

`summary.operation` values:

| Operation | Meaning |
|---|---|
| `append` | Only data files added, none removed. |
| `replace` | Files added and removed without changing table data (compaction, format change, relocation). |
| `overwrite` | Files added and removed as a logical overwrite. |
| `delete` | Data files removed / logically deleted, or delete files added. |

# Snapshot Lineage and Atomicity

- Multiple manifests can back one snapshot — this lets appends add just a
  new manifest ("fast append") instead of rewriting an existing one, lets a
  table mix multiple partition specs (one manifest per spec), and lets huge
  tables parallelize planning across manifests.
- A commit is atomic because it is nothing more than swapping which
  metadata.json (and thus which `current-snapshot-id`) the catalog points
  to. Readers that already loaded a metadata pointer are unaffected until
  they refresh — this is what gives snapshot isolation for reads with no
  locking.
- Because valid snapshots and their manifest lists are immutable and
  retained (until expired), reading an old `snapshot-id` reconstructs
  exactly that historical state — this is **time travel**. **Rollback** is
  simply setting `current-snapshot-id` back to an older, still-valid
  snapshot.

# Snapshot Log vs. Metadata Log

| Log | Tracks | Entry |
|---|---|---|
| `snapshot-log` | Changes to which snapshot is current | `{timestamp-ms, snapshot-id}` |
| `metadata-log` | Changes to the metadata.json file location itself | `{timestamp-ms, metadata-file}` |

When snapshots expire, entries in `snapshot-log` that precede an expired
snapshot should also be removed. `metadata-log` can independently be
truncated to a fixed size after each commit.

# Reliability Implications

Iceberg tracks the complete list of data files for each snapshot using a
persistent tree structure, and every write reuses as much of the prior
snapshot's metadata tree as possible rather than rewriting it — this gives:

- **Serializable isolation** — all changes occur in a linear history of
  atomic updates.
- **Reliable reads without locks** — readers always see a consistent
  snapshot.
- **Safe file-level operations** — compaction and late-arriving appends can
  be applied safely because commits are atomic.
- **O(1) RPCs to plan** a scan (read one snapshot's metadata) instead of
  O(n) directory listings.

See [reliability-and-concurrency.md](reliability-and-concurrency.md) for the
full optimistic-concurrency commit protocol.

# Citations

[1] [Apache Iceberg Table Spec — Snapshots](https://iceberg.apache.org/spec)
[2] [Apache Iceberg Documentation — Reliability](https://iceberg.apache.org/docs/latest/reliability)
[3] [Apache Iceberg Terms — Snapshot / Snapshot log](https://iceberg.apache.org/terms)
