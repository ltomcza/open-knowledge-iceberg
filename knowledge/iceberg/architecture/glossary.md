---
type: Iceberg Concept
title: Iceberg Glossary
description: Quick-lookup definitions of key Apache Iceberg terms — catalog, snapshot, manifest list, manifest file, partition spec, partition tuple, snapshot log, and more.
aliases: [iceberg terms, iceberg glossary, iceberg definitions, iceberg terminology]
tags: [iceberg, architecture, glossary, reference]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/terms
---

# Retrieval Notes

Quick-lookup reference — read this for a one-line definition of an Iceberg
term. For depth on any term, follow the cross-link to its dedicated
concept file.

# Summary

- Definitions below mirror the official Iceberg Terms page, lightly
  expanded and cross-linked to the deeper concepts in this bundle.
- Core hierarchy to remember: **Catalog** → tracks → **Table** (current
  metadata pointer) → has → **Snapshot** → lists → **Manifest list** →
  lists → **Manifest file(s)** → list → **Data / delete files**.

# Terms

| Term | Definition | See also |
|---|---|---|
| **Catalog** | Tracks a collection of tables (usually grouped into namespaces) by name, and — most importantly — tracks each table's *current* metadata location. The first thing any Iceberg client configures. Implementations include REST, Hive Metastore, JDBC, and Nessie (git-like, transactional). | [table-format-overview.md](table-format-overview.md), `/catalogs/rest-catalog.md` |
| **Snapshot** | The complete state of a table at some point in time — the set of all data files that made up the table then. Data files are grouped into manifests; a snapshot's manifests are listed in one manifest list. | [snapshots-and-versioning.md](snapshots-and-versioning.md) |
| **Manifest list** | A metadata file listing the manifest files that make up one table snapshot, with per-manifest summary info (partition value ranges, file counts) used to speed up planning. | [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md) |
| **Manifest file** | A metadata file listing a subset of the data files (or delete files) making up a snapshot. Each entry carries a partition tuple, column-level stats, and summary info used to prune files during scan planning. | [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md) |
| **Partition spec** | A description of how to derive partition values from a table's data — a list of source columns and transforms (e.g. `date(ts)` produces a date from a timestamp column `ts`). | [partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md), [partition-transforms-reference.md](partition-transforms-reference.md) |
| **Partition tuple** | The tuple/struct of partition values stored alongside each data file, produced by applying a partition spec to that file's row data. All rows in one data file share the same partition tuple. Unlike Hive, Iceberg stores these values typed/unmodified rather than as strings in file paths. | [partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md) |
| **Snapshot log (history table)** | The metadata log of `{timestamp, snapshot-id}` pairs recording how the table's *current* snapshot changed over time. Stored as `snapshot-log` in table metadata. | [snapshots-and-versioning.md](snapshots-and-versioning.md), [metadata-layer.md](metadata-layer.md) |
| **Table metadata (`metadata.json`)** | The root JSON file of a table's state: schema(s), partition spec(s), sort order(s), valid snapshots, and logs. Every change writes a new file; commits are atomic pointer swaps. | [metadata-layer.md](metadata-layer.md) |
| **Data file** | A file (Parquet, ORC, or Avro) containing actual table rows. | [table-format-overview.md](table-format-overview.md) |
| **Delete file** | A file encoding rows deleted by position or by column-value equality, without rewriting data files. As of v3, position-style deletes use binary deletion vectors instead of position delete files. | [row-level-deletes.md](row-level-deletes.md) |
| **REST catalog** | A server-side catalog exposed via a standardized REST API (Iceberg REST Open API spec), introduced in 0.14.0. Decouples catalog implementation details (auth, backend storage, custom logic) from the client — one client can talk to any compliant server. | `/catalogs/rest-catalog.md` |
| **Hidden partitioning** | Iceberg's approach of deriving partition values automatically via transforms rather than requiring an explicit, user-maintained partition column — avoiding Hive's classic silent-wrong-results failure mode. | [partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md) |
| **Sequence number** | A monotonically increasing long assigned to every successful commit, used to determine relative age of files — critical for knowing which delete files apply to which data files. | [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md) |
| **Branch / Tag** | Named, independently-retained references to snapshots — tags are fixed points, branches are mutable lineages. | [branching-and-tagging.md](branching-and-tagging.md) |
| **FileIO** | The storage abstraction interface Iceberg uses for metadata reads/writes, decoupling the core library from any specific object store or file system. | [file-io-and-encryption.md](file-io-and-encryption.md) |

# Citations

[1] [Apache Iceberg Terms](https://iceberg.apache.org/terms)
