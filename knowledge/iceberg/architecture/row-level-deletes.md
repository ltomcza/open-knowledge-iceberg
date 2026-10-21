---
type: Iceberg Concept
title: Row-Level Deletes
description: Copy-on-write vs. merge-on-read in Iceberg, the three delete encodings (deletion vectors, position delete files, equality delete files), and delete-file structure.
aliases: [copy-on-write, merge-on-read, position deletes, equality deletes, deletion vector, delete file, row-level updates]
tags: [iceberg, architecture, deletes, mor, cow, spec]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/spec
---

# Retrieval Notes

Read this for how Iceberg deletes/updates individual rows without
rewriting whole data files. For where delete files are tracked (delete
manifests), see [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md).
For which format version introduced which delete encoding, see
[metadata-layer.md](metadata-layer.md). For maintenance operations that
compact away accumulated deletes, see
`/maintenance/compaction-and-file-sizing.md`.

# Summary

- Row-level deletes let Iceberg delete or overwrite individual rows in
  **immutable** data files, without rewriting the file — added in **format
  v2**; not supported in v1.
- Two strategies for applying deletes at read time: **copy-on-write (COW)**
  rewrites affected data files immediately at write time (no delete files
  persist); **merge-on-read (MOR)** writes small delete files/vectors
  instead and merges them with data files at **read** time — cheaper
  writes, slightly more expensive reads until compacted.
- Three delete **encodings**: **deletion vectors** (v3+, binary bitmap,
  preferred), **position delete files** (v2, deprecated in v3), and
  **equality delete files** (v2+, still current).
- **Position-based** deletes identify a row by `(file_path, row position)`.
  **Equality-based** deletes identify rows by column value(s) (e.g. `id =
  5`) — they can delete rows in files that didn't exist yet when the delete
  was written, as long as the file's sequence number is older.
- Delete files are tracked in **delete manifests**, separate from data
  manifests, but sharing the same `manifest_entry` schema; delete manifests
  are scanned first during planning.
- At most **one deletion vector per data file per snapshot** — new deletes
  merge into the existing vector rather than creating a second one.

# Copy-on-Write vs. Merge-on-Read

| | Copy-on-write (COW) | Merge-on-read (MOR) |
|---|---|---|
| Write cost | High — must rewrite entire affected data file(s) | Low — write a small delete file/vector |
| Read cost | Low — data files are already "clean" | Higher — reader must merge deletes with data at scan time |
| Delete files produced? | No | Yes (position/equality delete files or deletion vectors) |
| Best for | Read-heavy tables, infrequent updates | Write-heavy / streaming tables, frequent small updates |
| Cleans up via | N/A (no accumulation) | Periodic compaction to fold deletes into data files — see `/maintenance/compaction-and-file-sizing.md` |

Both strategies operate on the same underlying spec feature (delete files);
COW vs. MOR is primarily a **writer/engine configuration choice**
(`write.delete.mode`, `write.update.mode`, `write.merge.mode` table
properties in engines like Spark), not a different spec mechanism.

# Delete Encodings

| Encoding | Introduced | Identifies deleted rows by | Status |
|---|---|---|---|
| Deletion vector | v3 | Bitmap of row positions within one referenced data file | Current, preferred |
| Position delete file | v2 | `(file_path, pos)` pairs, sorted | Deprecated in v3 (existing files remain valid; new ones must not be added) |
| Equality delete file | v2 | Column value(s) equal to a row | Current |

### Deletion Vectors (v3+)

- A binary bitmap (Roaring-bitmap-based: 64-bit positions split into a
  32-bit "key" + 32-bit sub-position, one 32-bit Roaring bitmap per key) —
  a set bit at position P means the row at P is deleted.
- Stored using the `deletion-vector-v1` Puffin blob type.
- Tracked in a delete manifest by `(file_path, content_offset,
  content_size_in_bytes)` of the containing Puffin file, plus
  `referenced_data_file`.
- **At most one DV per data file per snapshot** — writers must merge new
  deletes into the existing vector (or into legacy position delete files,
  which the DV then supersedes) rather than write a second one.

### Position Delete Files (v2, deprecated v3)

- Struct `file_position_delete`: `file_path` (string), `pos` (long, 0-based
  ordinal), optional `row` (the deleted row's values, for change-stream
  reconstruction).
- Must be sorted by `file_path` then `pos` (enables filter pushdown by file,
  and streaming filtering without buffering all deletes in memory).
- In v3+, existing position delete files remain valid but writers must
  encode new positional deletes as deletion vectors instead.

### Equality Delete Files (v2+)

- Store a subset of table columns (by field id) — the **delete columns** —
  listed in the manifest entry's `equality_ids`.
- A data row is deleted if its values match **all** delete columns of any
  row in an applicable equality delete file (an AND of equality
  predicates; `null` in a delete column matches `IS NULL`).
- Can be written as an **unpartitioned global delete** — applies across all
  partitions.
- Example: to delete `id = 4 AND category IS NULL`:
  ```
  equality_ids=[1, 2]

   1: id | 2: category | 3: name
  -------|-------------|---------
   4     | NULL        | Polar
  ```

# Applying Deletes at Scan Time

A delete only applies to a data file when, roughly:

| Delete type | Applies to a data file when |
|---|---|
| Deletion vector | Same `file_path` as `referenced_data_file`; data file's sequence number ≤ DV's sequence number; same partition. |
| Position delete file | Same `file_path` (if `referenced_data_file` set); data file's sequence number ≤ delete's sequence number; same partition; no DV already covers the file. |
| Equality delete file | Data file's sequence number **strictly less than** the delete's sequence number; same partition, **or** the delete file is unpartitioned (global). |

Special case: position deletes/DVs *can* apply to a data file from the
**same** commit (equal sequence numbers) — this allows deleting rows added
in the same transaction that adds them.

# Operational Notes

- Writers choose **delete granularity** (`write.delete.granularity`:
  `file` or `partition`) for position deletes — a read-cost vs file-count
  trade-off. Tuning detail and v3 deletion-vector benchmarks:
  [/performance/large-scale-merge-and-update-tuning.md](/performance/large-scale-merge-and-update-tuning.md).
- Cleanup after heavy MOR updates:
  [/maintenance/post-update-maintenance-runbook.md](/maintenance/post-update-maintenance-runbook.md).

# Citations

[1] [Apache Iceberg Table Spec — Row-level Deletes / Delete Formats](https://iceberg.apache.org/spec)
[2] [Apache Iceberg Table Spec — Scan Planning](https://iceberg.apache.org/spec)
