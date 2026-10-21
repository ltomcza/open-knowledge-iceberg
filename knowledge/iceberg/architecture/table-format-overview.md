---
type: Iceberg Concept
title: Apache Iceberg Table Format — Overview
description: What Apache Iceberg is, the problems it solves versus Hive-style tables, and the layered metadata architecture that underlies every Iceberg table.
aliases: [what is iceberg, iceberg table format, iceberg vs hive, iceberg architecture, open table format]
tags: [iceberg, architecture, overview, table-format]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest
---

# Retrieval Notes

Read this first for orientation on Iceberg's architecture. For the byte-level
structure of each layer, see the deeper concepts it links to:
[metadata-layer.md](metadata-layer.md), [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md),
[snapshots-and-versioning.md](snapshots-and-versioning.md). For write correctness under
concurrency, see [reliability-and-concurrency.md](reliability-and-concurrency.md).

# Summary

- Apache Iceberg is an **open table format** for huge analytic datasets — it
  adds SQL-table semantics on top of files in a distributed file system or
  object store (S3, GCS, ADLS, HDFS), for engines like Spark, Trino,
  PrestoDB, Flink, Hive, and Impala.
- Iceberg tracks **individual data files**, not directories — unlike Hive
  tables, which infer table state by listing directories. This is the root
  fix for Hive's correctness and performance problems on eventually
  consistent object stores.
- The architecture is a **layered metadata tree**: catalog pointer →
  `metadata.json` (table metadata) → manifest list → one or more manifest
  files → data files (and delete files). Each layer narrows down which files
  a query actually needs to read.
- All table-state changes are **atomic metadata swaps**: a writer produces a
  new `metadata.json` and the catalog atomically repoints the table to it.
  This gives serializable isolation without locks.
- Iceberg is a **specified, open standard** ([iceberg.apache.org/spec](https://iceberg.apache.org/spec)),
  developed at the Apache Software Foundation, so independent engines and
  languages can implement compatible readers/writers.
- Key user-facing wins: safe schema evolution with no side effects, hidden
  partitioning (queries don't need to know the physical layout), partition
  layout evolution without rewriting data, time travel, and version
  rollback.

# Why Iceberg vs. Hive Tables

| Hive-style tables | Iceberg tables |
|---|---|
| Table state = directory listing; partitions tracked as literal columns/paths in a metastore. | Table state = an explicit, versioned list of files recorded in metadata. |
| Planning requires listing directories: O(n) with number of partitions/files. | Planning reads a manifest list + manifests: O(1) remote calls, no listing. |
| Eventually-consistent object stores (e.g., S3 listing) can produce incorrect or stale results. | No reliance on listing or renames — safe on any object store. |
| Partition columns are explicit and user-supplied; wrong values silently corrupt query results. | [Hidden partitioning](partitioning-and-hidden-partitioning.md) — Iceberg derives and validates partition values itself. |
| Schema changes (rename, reorder) can silently corrupt data or require full rewrites. | [Schema evolution](schema-evolution.md) is a metadata-only operation with no side effects. |
| No native concept of atomic multi-file commits. | Every write is a single atomic commit producing a new [snapshot](snapshots-and-versioning.md). |
| Changing partitioning requires a new table + query rewrite. | Partition spec can evolve in place; old and new layouts coexist. |

# The Layered Architecture

```
Catalog (tracks current metadata pointer per table)
  └── metadata.json               (table metadata: schema, partition specs, snapshot list, ...)
        └── manifest list          (one per snapshot: lists manifests + partition-level stats)
              └── manifest file(s) (list data/delete files + per-file column stats)
                    └── data file(s)   (Parquet / ORC / Avro)
                    └── delete file(s) (row-level deletes, v2+)
```

- **Catalog** — the pluggable component that maps a table name to the
  location of its *current* `metadata.json` (e.g., REST catalog, Hive
  Metastore, JDBC, Nessie, AWS Glue). See `/catalogs/` concepts for
  catalog-specific detail.
- **Table metadata (`metadata.json`)** — the root of a table's state:
  format version, table UUID, schema(s), partition spec(s), sort order(s),
  the list of valid snapshots, and pointers to the current snapshot. See
  [metadata-layer.md](metadata-layer.md).
- **Manifest list** — one per snapshot; an Avro file listing which manifest
  files make up that snapshot, with summary stats per manifest used to prune
  entire manifests during planning. See [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md).
- **Manifest file** — an Avro file listing a subset of data or delete files,
  each with its partition tuple and column-level stats (min/max, null
  counts), used to prune individual files. See [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md).
- **Data / delete files** — the actual row data (Parquet, ORC, or Avro) and,
  for v2+, delete files that mark rows deleted without rewriting data files.
  See [row-level-deletes.md](row-level-deletes.md).

Because the tree records the **complete list of files** at each snapshot,
planning a scan never requires listing a file system — only reading the
metadata tree, which is small relative to the data.

# Reliability and Performance at a Glance

- **Serializable isolation** — readers see a consistent snapshot; writes are
  atomic and never partially visible. See [reliability-and-concurrency.md](reliability-and-concurrency.md).
- **O(1) scan planning** — planning cost doesn't grow with the number of
  partitions, only (roughly) with the number of manifests touched.
- **Optimistic concurrency** — multiple writers can operate concurrently;
  conflicting commits retry rather than block. See [reliability-and-concurrency.md](reliability-and-concurrency.md).
- **Works with any object store** — no reliance on atomic rename or
  consistent listing (S3, GCS, ADLS, HDFS all work).

# Citations

[1] [Apache Iceberg Documentation — overview](https://iceberg.apache.org/docs/latest)
[2] [Apache Iceberg Table Spec](https://iceberg.apache.org/spec)
