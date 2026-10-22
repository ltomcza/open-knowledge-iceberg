---
type: Iceberg Catalog
title: Nessie Catalog
description: Nessie's git-like versioned catalog — catalog-level branches/tags/commits distinct from Iceberg's own table-level branching, plus configuration.
aliases: [NessieCatalog, project nessie, nessie iceberg, git-like catalog, catalog branching, multi-table transactions]
tags: [iceberg, catalog, nessie, versioning, branching]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/nessie
---

# Retrieval Notes

Read this first for **catalog-level git-like versioning** (branches/tags
spanning the whole catalog, multi-table commits). This is a **different
concept** from Iceberg table-level branches/tags (created with `ALTER TABLE
... CREATE BRANCH`, see [/architecture/branching-and-tagging.md](/architecture/branching-and-tagging.md) or
[hive-catalog.md](/catalogs/hive-catalog.md)'s branch/tag DDL examples) — do
not conflate the two. For generic catalog properties and how to choose a
catalog, see [catalogs-overview.md](/catalogs/catalogs-overview.md).

# Summary

- Nessie is a **separate server** that provides a catalog with git-like
  semantics — branches, tags, and commits — at the level of the *entire
  catalog* (many tables/namespaces at once), not per-table.
- Every Iceberg transaction against a Nessie-backed table becomes **one
  Nessie commit**; this history can be listed, merged, or cherry-picked
  across branches using the Nessie CLI/client, independent of Iceberg's own
  APIs.
- Required config: `warehouse` (table storage root, like any catalog), `uri`
  (Nessie server base URL, e.g. `http://localhost:19120/api/v2`), and
  optional `ref` (the Nessie branch/tag to operate against).
- Branching enables **loosely-coupled multi-table transactions** (commit a
  sequence of changes on a branch, then merge atomically to `main`) and safe
  **experimentation** (test schema/partition evolution on a branch, drop it
  if wrong) — but this is *not* a true multi-table ACID transaction; each
  operation is still its own Iceberg commit, just grouped in Nessie history.
- Nessie requires its own SQL extensions
  (`NessieSparkSessionExtensions`) alongside Iceberg's, and its own running
  server — it is materially more operational surface than a native catalog.
- **Danger**: regular Iceberg table maintenance (snapshot expiry, compaction)
  is complicated by Nessie's branching model — consult Nessie's management
  services docs before running maintenance operations.

# Configuration

| Property | Required | Description |
|---|---|---|
| `warehouse` | yes | File path root where this catalog stores tables (same as any catalog). |
| `uri` | yes | Nessie server base URI, e.g. `http://localhost:19120/api/v2`. |
| `ref` | no | Nessie branch or tag to operate in (defaults to the server's default, typically `main`). |
| `type` | yes (engine-level) | `nessie` to select `NessieCatalog`. |

Java:

```java
Map<String, String> options = new HashMap<>();
options.put("warehouse", "/path/to/warehouse");
options.put("ref", "main");
options.put("uri", "https://localhost:19120/api/v2");
Catalog nessieCatalog = CatalogUtil.loadCatalog(
    "org.apache.iceberg.nessie.NessieCatalog", "nessie", options, hadoopConfig);
```

Spark:

```
spark.sql.catalog.nessie.warehouse=/path/to/warehouse
spark.sql.catalog.nessie.uri=http://localhost:19120/api/v2
spark.sql.catalog.nessie.ref=main
spark.sql.catalog.nessie.type=nessie
spark.sql.catalog.nessie=org.apache.iceberg.spark.SparkCatalog
spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions,org.projectnessie.spark.extensions.NessieSparkSessionExtensions
```

Starting Spark with both runtimes:

```bash
bin/spark-sql \
  --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.12.0,org.projectnessie.nessie-integrations:nessie-spark-extensions-3.5_2.12:0.108.8" \
  --conf spark.sql.extensions="org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions,org.projectnessie.spark.extensions.NessieSparkSessionExtensions"
```

Flink (Python API):

```python
table_env.execute_sql(
    "CREATE CATALOG nessie_catalog WITH ("
    "'type'='iceberg', "
    "'catalog-impl'='org.apache.iceberg.nessie.NessieCatalog', "
    "'uri'='http://localhost:19120/api/v2', "
    "'ref'='main', "
    "'warehouse'='/path/to/warehouse')"
)
```

The catalog name (`nessie` above) is arbitrary — what matters is `type` (or
`catalog-impl`) plus the required properties.

# What Nessie adds on top of a plain Iceberg catalog

- **Multi-table transactions** (loosely coupled — see caveat below).
- **Git-like operations** — create/delete/merge branches, commit history,
  diffs — performed via the `NessieClient` (Java), Python client, or Nessie
  CLI, not through Iceberg's own catalog API.
- **Hive-like metastore capabilities** for namespace/table management.
- Tables are addressed by an arbitrary-length namespace + table name (e.g.
  `data.base.name.table`); namespaces must be explicitly created.

## Loosely-coupled transactions

Create a branch, perform a sequence of commits on it, then merge back to
`main` atomically. Downstream consumers see the merge as multiple changes
appearing at once — but this is a **fast-forward merge of independent
single-table transactions**, not a genuine multi-table ACID commit; each
underlying operation is still its own distinct Iceberg transaction and
Nessie commit.

## Experimentation

Test risky changes (schema evolution, partition evolution, performance
benchmarking) on a branch before merging to `main`; drop the branch if the
change doesn't work out, with zero impact on `main`.

# Limitations

- Requires running and operating a Nessie server as separate infrastructure.
- Iceberg's built-in maintenance operations (expire snapshots, remove orphan
  files, compaction) need extra care under Nessie's branching model — see
  Nessie's [Management Services](https://projectnessie.org/features/management/)
  docs before running them.
- Only single-table transactions are currently available from Iceberg's own
  API even though Nessie *commits* can span many tables — true multi-table
  transactions are a listed future improvement, not yet implemented.

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — how Nessie fits
  among other catalog choices, generic catalog properties.
- [/architecture/branching-and-tagging.md](/architecture/branching-and-tagging.md) — Iceberg's own per-table
  branches/tags/snapshots, a different mechanism from Nessie's catalog-level
  branching described here.

# Citations

[1] [Iceberg Nessie Integration](https://iceberg.apache.org/docs/latest/nessie)
