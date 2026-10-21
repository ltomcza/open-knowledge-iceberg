---
type: Maintenance Guide
title: Remove Orphan Files
description: What orphan files are, how remove_orphan_files finds and deletes them, and the safety considerations around retention age and in-flight writes.
aliases: [remove_orphan_files, orphan files, deleteOrphanFiles, dangling files, failed job cleanup, garbage collection]
tags: [iceberg, maintenance, garbage-collection, orphan-files, safety]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/maintenance/
---

# Retrieval Notes

Read this when storage usage doesn't match what
[expire-snapshots](/maintenance/expire-snapshots.md) accounts for, or after
job failures/crashed writers leave stray files behind. For the exact `CALL`
syntax and every argument, see
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) (procedure:
`remove_orphan_files`).

# Summary

- **Orphan files** are files sitting under a table's storage location that
  are *not referenced by any table metadata* — they contribute nothing to
  correctness but still cost storage.
- Typical causes: task/job failures in Spark or other engines that write a
  file before failing to commit, and cases where normal snapshot expiration
  can't determine a file is unreferenced.
- `remove_orphan_files` finds candidates by comparing an actual file
  listing (or a supplied file list view) of the table's data/metadata
  directories against everything referenced by table metadata, then deletes
  what doesn't match.
- **Safety is the central concern**: files younger than a retention window
  are excluded by default, because an in-flight write can look identical to
  an orphan before its commit lands.
- Default retention window is **3 days**; this is deliberately conservative
  and should not be shortened below your longest expected write duration.
- Support a `dry_run` mode — always dry-run in production before deleting.

# What Orphan Files Are

Iceberg commits are atomic at the metadata level: a writer stages data
files, then atomically swaps in a new metadata pointer. If a job dies after
writing data files but before committing (or a writer crashes mid-write),
those staged files are never referenced by any snapshot and will never be
cleaned up by ordinary [expire-snapshots](/maintenance/expire-snapshots.md),
which only removes files that *were* referenced by an expired snapshot.
These abandoned files just sit in the table's storage location as pure
waste — "orphaned" from any live or historical metadata.

# How the Removal Action Works

1. List all files actually present under the table's location (or a given
   `location`, or a supplied `file_list_view` dataset to skip an expensive
   directory listing on huge tables).
2. Compare against every file path referenced anywhere in current table
   metadata (all live and expired-but-not-yet-GC'd snapshots' manifests).
3. Anything present on disk but absent from metadata, and older than
   `older_than`, is reported as orphan and (unless `dry_run`) deleted.

```sql
-- dry run first: list candidates without deleting
CALL catalog_name.system.remove_orphan_files(table => 'db.sample', dry_run => true);

-- actually remove orphans under the default table location
CALL catalog_name.system.remove_orphan_files(table => 'db.sample');
```

Key options (full reference in
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md)):

| Option | Default | Purpose |
|---|---|---|
| `older_than` | 3 days ago | Only files older than this are candidates |
| `location` | table location | Scope the scan to a subdirectory |
| `dry_run` | false | Report candidates without deleting |
| `file_list_view` | — | Supply a precomputed file listing instead of doing a live directory listing (much cheaper on huge tables) |
| `prefix_mismatch_mode` | ERROR | Behavior when a file's scheme/authority prefix doesn't match metadata (`ERROR`, `IGNORE`, `DELETE`) |
| `equal_schemes` / `equal_authorities` | `s3a,s3n → s3` | Treat different URI schemes/authorities as equivalent when comparing paths |

# Safety Considerations

- **Retention window vs. write duration**: it is dangerous to set
  `older_than` shorter than the time any write in your system can take to
  complete. A long-running write task can create a file, then stall past a
  short retention window — the file looks orphaned (unreferenced) even
  though it's about to be committed, and deleting it corrupts that write.
  The 3-day default is intentionally generous; only shorten it if you're
  certain no write ever takes that long.
- **Path/authority drift**: Iceberg compares string representations of
  paths. If the filesystem's path representation changes over time (e.g.
  HDFS authority/namenode changes) without a corresponding metadata update,
  live files can appear to not match and be wrongly deleted. Verify entries
  in metadata tables match current filesystem listings before running this
  in such environments, and prefer `prefix_mismatch_mode => 'IGNORE'` over
  blind `DELETE` when scheme/authority mismatches are expected.
- **Cost on huge tables**: a full directory listing can be slow at scale;
  use `file_list_view` with a precomputed file inventory when available.
- **Always dry-run first** in any environment where the blast radius of a
  mistaken deletion matters.

# Citations

[1] [Apache Iceberg — Maintenance: Delete Orphan Files](https://iceberg.apache.org/docs/latest/maintenance/#delete-orphan-files)
[2] [Apache Iceberg — Spark Procedures: remove_orphan_files](https://iceberg.apache.org/docs/latest/spark-procedures/#remove_orphan_files)
