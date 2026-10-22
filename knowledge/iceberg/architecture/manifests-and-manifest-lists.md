---
type: Iceberg Concept
title: Manifests and Manifest Lists
description: Structure of Iceberg manifest list vs. manifest files — sequence numbers, data vs. delete manifests, and the partition-level summaries used for file pruning during scan planning.
aliases: [manifest file, manifest list, data manifest, delete manifest, manifest_entry, field_summary, scan planning pruning]
tags: [iceberg, architecture, manifests, manifest-list, scan-planning, spec]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/spec
---

# Retrieval Notes

Read this for the two Avro-file layers sitting between `metadata.json` and
data files. For the outer layers see [table-format-overview.md](table-format-overview.md)
and [metadata-layer.md](metadata-layer.md). For the snapshot that owns a
manifest list, see [snapshots-and-versioning.md](snapshots-and-versioning.md).
For delete-file specifics tracked inside delete manifests, see
[row-level-deletes.md](row-level-deletes.md).

# Summary

- A **manifest list** is a per-snapshot Avro file listing the **manifest
  files** that make up that snapshot, with per-manifest summary stats used
  to skip whole manifests during planning.
- A **manifest file** is an Avro file listing **data files or delete files**
  (never both — "data manifest" vs. "delete manifest", tracked via a
  `content` field), each entry carrying the file's partition tuple and
  column-level stats used to skip individual files.
- Manifests are **reused across snapshots** — an append typically writes
  only a new manifest for the new files, while existing manifests are
  simply re-referenced by the new manifest list. This keeps commits cheap.
- A manifest is scoped to **one partition spec**; when the partition spec
  changes, old files stay in the old manifest and new files go to fresh
  manifests written under the new spec.
- **Sequence numbers** record relative write order and are what determines
  which delete files apply to which data files (in general a delete applies
  only to *older* data — strictly lower data sequence number — in the same
  partition; position deletes and deletion vectors also apply at an equal
  sequence number, and unpartitioned equality deletes are global — see
  [row-level-deletes.md](row-level-deletes.md)).
- Manifest-list `partitions` summaries (field_summary) let scan planning
  skip an entire manifest without opening it, using per-partition-field
  lower/upper bounds and null/NaN flags.

# Manifest List

One manifest list is written **per commit attempt** (a new one every time,
because the set of manifests always changes for a new snapshot). Its
`manifest_file` entries include:

| Field | Type | Purpose |
|---|---|---|
| `manifest_path` | string | Location of the manifest file. |
| `manifest_length` | long | Manifest file size in bytes. |
| `partition_spec_id` | int | Which partition spec (from table metadata) the manifest was written with. |
| `content` | int | `0: data`, `1: deletes`. |
| `sequence_number` | long | Sequence number when the manifest was added to the table. |
| `min_sequence_number` | long | Min data sequence number among live files in the manifest. |
| `added_snapshot_id` | long | Snapshot ID that added this manifest. |
| `added_files_count` / `existing_files_count` / `deleted_files_count` | int | File counts by status, used to skip manifests with no relevant files. |
| `added_rows_count` / `existing_rows_count` / `deleted_rows_count` | long | Row counts by status. |
| `partitions` | `list<field_summary>` | Per-partition-field summary (see below) — the key pruning structure. |
| `key_metadata` | binary | Encryption key metadata, if the table is encrypted. |

`field_summary` (one entry per partition field in the manifest's spec):

| Field | Type | Purpose |
|---|---|---|
| `contains_null` | boolean | Whether any partition value for this field is null. |
| `contains_nan` | boolean | Whether any partition value is NaN. |
| `lower_bound` / `upper_bound` | bytes | Min/max non-null, non-NaN partition value for the field across all files in the manifest. |

This lets a planner discard an entire manifest (potentially thousands of
files) using only the manifest list, without opening a single manifest file.

# Manifest File

A manifest stores `manifest_entry` records — one per data or delete file:

| Field | Type | Notes |
|---|---|---|
| `status` | int | `0: EXISTING`, `1: ADDED`, `2: DELETED`. Deletes here are informational (not applied to scans). |
| `snapshot_id` | long | Snapshot that added (or logically deleted) the file. |
| `sequence_number` | long | Data sequence number (v2+); inherited from the manifest list if null. |
| `file_sequence_number` | long | Sequence number of the snapshot that added the file; also inheritable. |
| `data_file` | struct | The actual file entry — see below. |

The `data_file` struct (selected fields):

| Field | Type | Purpose |
|---|---|---|
| `content` | int | `0: DATA`, `1: POSITION DELETES`, `2: EQUALITY DELETES`. |
| `file_path` | string | Full URI of the file. |
| `file_format` | string | `avro`, `orc`, `parquet`, or `puffin`. |
| `partition` | struct | Partition value tuple, typed per the manifest's partition spec. |
| `record_count` | long | Row count (or deletion-vector cardinality). |
| `file_size_in_bytes` | long | File size. |
| `column_sizes`, `value_counts`, `null_value_counts`, `nan_value_counts` | maps keyed by column id | Per-column stats used for filtering. |
| `lower_bounds` / `upper_bounds` | maps keyed by column id | Per-column min/max, serialized binary — the primary predicate-pushdown mechanism. |
| `split_offsets` | list\<long\> | Row-group/split offsets within the file. |
| `equality_ids` | list\<int\> | For equality delete files: which columns define row equality. |
| `sort_order_id` | int | Sort order the file was written with, if any. |

A manifest file must store the **schema and partition spec it was written
with** as Avro key-value metadata (`schema`, `schema-id`, `partition-spec`,
`partition-spec-id`, `format-version`, `content`), so a reader can interpret
older manifests correctly even after the table's schema/spec has moved on.

# Data vs. Delete Manifests

Because a manifest holds only one of data files or delete files, delete
manifests are scanned first during job planning so their partition/sequence
information can be matched against data files without mixing entry types.
Both manifest kinds share the same `manifest_entry` schema.

# Sequence Numbers and Reuse

- Every successful commit is assigned the next monotonically increasing
  **sequence number**, written into the new snapshot.
- New file entries are written with `sequence_number = null` in the
  manifest; the true value is **inherited** from the manifest list at read
  time. This lets the same manifest file be reused unmodified across commit
  retries — only the (cheap) manifest list needs rewriting to change the
  sequence number.
- When an existing file is copied into a *new* manifest (status
  `EXISTING`), its already-assigned sequence number must be written
  explicitly (no longer inheritable), so it never changes after first
  assignment.

# Citations

[1] [Apache Iceberg Table Spec — Manifests](https://iceberg.apache.org/spec)
[2] [Apache Iceberg Table Spec — Manifest Lists](https://iceberg.apache.org/spec)
[3] [Apache Iceberg Terms — Manifest file / Manifest list](https://iceberg.apache.org/terms)
