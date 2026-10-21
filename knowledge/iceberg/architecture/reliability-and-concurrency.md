---
type: Iceberg Concept
title: Reliability and Concurrency
description: Iceberg's ACID guarantees, serializable snapshot isolation, optimistic concurrency control on commit, and how conflicting concurrent writes are resolved.
aliases: [ACID guarantees, optimistic concurrency, serializable isolation, concurrent writers, commit conflict, retry validation]
tags: [iceberg, architecture, reliability, concurrency, acid, isolation]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/reliability
---

# Retrieval Notes

Read this for how Iceberg guarantees correctness under concurrent writers
and eventually-consistent object stores. For what a commit actually swaps,
see [snapshots-and-versioning.md](snapshots-and-versioning.md) and
[metadata-layer.md](metadata-layer.md). For the general architecture this
builds on, see [table-format-overview.md](table-format-overview.md).

# Summary

- Iceberg was designed to fix correctness problems in **Hive tables on S3**:
  Hive tracks partitions in a metastore and files via listing, which is
  slow (O(n) with partition count) and can be **wrong** on eventually
  consistent object stores.
  Iceberg instead tracks the **complete list of files per snapshot** in a
  persistent tree, so no listing is ever required to plan a scan.
- **Serializable isolation**: all table changes form a linear history of
  atomic updates; readers never see partial or uncommitted changes and
  never need to acquire a lock.
- **Reliable reads without locks**: a reader loads a consistent snapshot at
  refresh time and is unaffected by later writes until it refreshes again.
- **Optimistic concurrency control (OCC)** governs writes: each writer
  assumes it's alone, builds new metadata, and tries to atomically swap the
  table's metadata pointer. If another writer already committed, the swap
  fails and the writer **retries** against the new current state.
- Retries are made cheap by structuring commits as **reusable work +
  validated assumptions** — e.g. a new manifest written for an append can be
  reused across retries; only the manifest list (cheap) needs rewriting.
- Different operations have different **retry-safety conditions** —
  appends can (almost) always retry; replace/delete/schema-changing
  operations must first verify their assumptions still hold against the new
  current state.
- Works with **any object store** (S3, GCS, ADLS, HDFS) because it never
  relies on directory listing or atomic rename for correctness (rename is
  only used, optionally, for the legacy/deprecated file-system-table commit
  scheme).

# Why This Beats Hive-on-S3

| Problem with Hive on S3 | Iceberg's fix |
|---|---|
| Atomic multi-file changes to a table are impossible (metastore + FS are separate sources of truth) | A commit is one atomic pointer swap of `metadata.json`; the whole file list changes together. |
| Eventually-consistent listing can return stale/incomplete results | Iceberg never lists to plan; it reads an explicit file list from metadata. |
| Job planning requires O(n) listing calls (n = partitions) | Planning is O(1) RPCs — read one manifest list + relevant manifests. |
| No safe way to compact small files or append late data concurrently | Atomic commits + OCC make these safe by construction. |

# Optimistic Concurrency Protocol

1. A writer reads the current table metadata (version `V`) and builds a new
   metadata tree (`V+1`) based on it — assuming no one else changes `V` in
   the meantime.
2. The writer attempts to **atomically swap** the table's metadata pointer
   from `V` to `V+1` (mechanism depends on the catalog — see below).
3. **If the swap succeeds**: `V+1` is now current; commit is done.
4. **If the swap fails** (another writer already committed a different
   `V+1`): the writer **retries** by rebuilding its change against the new
   current version, if the operation's retry conditions are still met.

# Retry Validation by Operation Type

| Operation | Retry condition |
|---|---|
| Append | No requirements — can (almost) always be reapplied. |
| Replace (e.g. compaction, format change) | The files being replaced/deleted must still be present in the new current table. |
| Delete | Specific files targeted for deletion must still be present; expression-based deletes (`WHERE ts < X`) can always reapply. |
| Schema / partition spec change | The schema must not have changed between the writer's base version and the new current version. |

If validation fails, the writer must fail (not silently produce wrong
results) rather than commit an inconsistent change.

# Cost of Retries

Writers are structured to avoid re-doing expensive work on retry. Example:
an append creates a new manifest file for the newly written data files;
that manifest doesn't need to be rewritten just because the manifest *list*
had to change on retry — only the (cheap) manifest list is regenerated.
This is closely tied to sequence-number inheritance — see
[manifests-and-manifest-lists.md](manifests-and-manifest-lists.md).

# How the Atomic Swap Is Implemented

The spec does not mandate one mechanism — it depends on the catalog:

| Catalog style | Atomic swap mechanism |
|---|---|
| File-system tables (deprecated, removed in v4) | Atomic file rename, e.g. HDFS `rename` from a unique staged file to `v<V+1>.metadata.json`. |
| Metastore tables | Check-and-put against a pointer stored in a metastore/DB (Hive Metastore, JDBC, Glue, etc.). |
| REST catalog | Server-side check-and-swap exposed via the REST commit API. |

# Citations

[1] [Apache Iceberg Documentation — Reliability](https://iceberg.apache.org/docs/latest/reliability)
[2] [Apache Iceberg Table Spec — Optimistic Concurrency](https://iceberg.apache.org/spec)
[3] [Apache Iceberg Table Spec — Commit Conflict Resolution and Retry](https://iceberg.apache.org/spec)
