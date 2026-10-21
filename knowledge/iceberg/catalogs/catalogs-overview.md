---
type: Iceberg Catalog
title: Iceberg Catalogs Overview
description: What an Iceberg catalog does, the available catalog implementations, and the generic catalog properties shared across them.
aliases: [iceberg catalog, catalog-impl, which catalog to use, catalog properties, custom catalog, metastore]
tags: [iceberg, catalog, architecture, metadata]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/catalog-properties
---

# Retrieval Notes

Read this first when deciding **which catalog implementation to use** or
**how catalog properties are structured** in general. For the specifics of a
particular catalog, go to its dedicated concept instead:
[REST catalog](/catalogs/rest-catalog.md),
[Hive catalog](/catalogs/hive-catalog.md),
[Glue catalog / S3FileIO](/catalogs/glue-catalog-and-s3.md),
[Nessie catalog](/catalogs/nessie-catalog.md),
[JDBC catalog](/catalogs/jdbc-catalog.md). For table-level (not catalog-level)
configuration, see [table properties reference](/catalogs/table-properties-reference.md).
For how Iceberg's metadata layer (metadata.json, manifest lists, manifests)
relates to what a catalog tracks, see `/architecture/metadata-layer.md`.

# Summary

- An Iceberg **catalog** is the single source of truth for **which metadata
  file is the current one** for a given table — it maps a table identifier
  (`namespace.table`) to the location of its latest `metadata.json`.
- Every catalog implementation must support an **atomic compare-and-swap**
  (or equivalent locking) on that pointer, so concurrent writers can commit
  safely — this atomicity guarantee is the entire reason a catalog exists,
  rather than just tracking table location on a filesystem.
- Iceberg ships with built-in catalogs (Hive, Hadoop/filesystem, REST, AWS
  Glue, AWS DynamoDB, JDBC, Nessie) and supports fully custom catalogs via
  `catalog-impl`.
- The **REST catalog** is the emerging standard: it decouples clients from a
  specific metastore implementation and is now the recommended default for
  new deployments (see [rest-catalog.md](/catalogs/rest-catalog.md)).
- A small set of **generic catalog properties** (`warehouse`, `uri`,
  `catalog-impl`, `io-impl`, `clients`, caching, locking) apply across nearly
  every catalog implementation; catalog-specific properties layer on top.
- Compute engines (Spark, Flink, Hive) pass catalog properties through to the
  catalog's `initialize(name, properties)` method — the property names are
  the same regardless of which engine loads the catalog.

# What a catalog does

An Iceberg table's state at any point in time is fully described by one
`metadata.json` file. Reading a table means finding that file; writing means
producing a new one and atomically swapping the pointer to it. The catalog is
the component that owns this pointer and provides:

1. **Lookup** — resolve `namespace.table` -> current metadata file location.
2. **Atomic commit** — a compare-and-swap (or transactional update) so that
   two concurrent writers can't both "win" and silently overwrite each
   other's changes. One must fail and retry against the new state.
3. **Namespace/table management** — create, drop, rename, list tables and
   namespaces.

Contrast this with `HadoopTables` / path-based tables, which have **no
catalog** at all — the table is identified purely by its filesystem path, and
atomicity on non-atomic filesystems (like S3) has to be bolted on with an
external lock manager (see [Lock catalog properties](#lock-catalog-properties)
below and `/catalogs/glue-catalog-and-s3.md` for the DynamoDB lock manager).

# Choosing a catalog implementation

| Catalog | `type` value | Best fit |
|---|---|---|
| REST | `rest` | Vendor-neutral, multi-engine, multi-language; the recommended default. See [rest-catalog.md](/catalogs/rest-catalog.md). |
| Hive Metastore | `hive` | Existing Hadoop/Hive ecosystem investment. See [hive-catalog.md](/catalogs/hive-catalog.md). |
| AWS Glue | `glue` | AWS-native stack (Athena, EMR, Redshift, Lake Formation). See [glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md). |
| AWS DynamoDB | n/a (`catalog-impl`) | High write throughput, need secondary indexes on table properties. See [glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md). |
| JDBC | `jdbc` | Existing relational DB (Postgres/MySQL/RDS) to reuse as metastore. See [jdbc-catalog.md](/catalogs/jdbc-catalog.md). |
| Nessie | `nessie` | Want git-like branching/tagging *of the whole catalog*, multi-table transactions. See [nessie-catalog.md](/catalogs/nessie-catalog.md). |
| Hadoop (filesystem) | `hadoop` | Simple/dev setups; no external service, but weak atomicity on object stores without a lock manager. |
| Custom | `catalog-impl` | None of the above fit; implement `Catalog`/`BaseMetastoreCatalog` yourself. |

# Common catalog properties

These apply across nearly all catalog implementations (set as
`spark.sql.catalog.<name>.<property>` in Spark, or directly as Java catalog
properties):

| Property | Default | Description |
|---|---|---|
| `catalog-impl` | null | A custom `Catalog` implementation class to use by an engine. |
| `io-impl` | null | A custom `FileIO` implementation class to use in a catalog. |
| `warehouse` | null | Root path of the data warehouse (base location for new tables). |
| `uri` | null | A URI string — e.g. Hive metastore thrift URI or REST base URL. |
| `clients` | 2 | Client pool size. |
| `cache-enabled` | true | Whether to cache catalog entries. |
| `cache.expiration-interval-ms` | 30000 | How long catalog entries are locally cached, in ms; `0` disables caching, negative disables expiration. |
| `metrics-reporter-impl` | `org.apache.iceberg.metrics.LoggingMetricsReporter` | Custom `MetricsReporter` implementation. |
| `unique-table-location` | false | Whether to use a unique location for new tables. |
| `encryption.kms-impl` | null | Custom `KeyManagementClient` implementation for KMS interactions. |

`HadoopCatalog` and `HiveCatalog` read these in their constructors; any other
custom catalog reads them via `Catalog.initialize(catalogName,
catalogProperties)`. Spark maps its session properties to catalog properties
directly; Flink passes them through the `CREATE CATALOG` statement.

## Lock catalog properties

Used by catalog implementations that need an external lock for atomic
commits (notably `HadoopCatalog`/`HadoopTables` on non-atomic filesystems
like S3):

| Property | Default | Description |
|---|---|---|
| `lock-impl` | null | A custom lock manager implementation; interface depends on the catalog used. |
| `lock.table` | null | An auxiliary table for locking, e.g. an AWS DynamoDB lock table. |
| `lock.acquire-interval-ms` | 5000 | Interval to wait between each attempt to acquire a lock. |
| `lock.acquire-timeout-ms` | 180000 (3 min) | Maximum time to try acquiring a lock. |
| `lock.heartbeat-interval-ms` | 3000 | Interval to wait between each heartbeat after acquiring a lock. |
| `lock.heartbeat-timeout-ms` | 15000 | Maximum time without a heartbeat to consider a lock expired. |

For `HadoopTables` (tables with no catalog at all), these same properties can
be set prefixed with `iceberg.tables.hadoop.` to enable atomic commits on
S3-like filesystems — e.g. `iceberg.tables.hadoop.lock-impl` set to
`org.apache.iceberg.aws.dynamodb.DynamoDbLockManager`.

# Writing a custom catalog

If no built-in catalog fits, extend `BaseMetastoreCatalog` +
`BaseMetastoreTableOperations`:

```java
class CustomTableOperations extends BaseMetastoreTableOperations {
  // doRefresh(): look up the current metadata location and call refreshFromMetadataLocation(...)
  // doCommit(base, metadata): atomically swap the metadata pointer via your service
  // io(): return the FileIO used to read/write metadata files
}

public class CustomCatalog extends BaseMetastoreCatalog {
  // newTableOps(TableIdentifier): return a CustomTableOperations
  // defaultWarehouseLocation(TableIdentifier): compute the default table path
  // dropTable / renameTable: delegate to your metastore service
  // initialize(String name, Map<String, String> properties): read config
}
```

Requirements:

- `CustomCatalog` needs a no-arg constructor to be dynamically loaded; engines
  call `initialize(name, properties)` after construction.
- In Spark/Flink, load it by setting the `catalog-impl` catalog property to
  the class's fully qualified name.
- In Hive/MapReduce, implement `org.apache.iceberg.mr.CatalogLoader` and set
  the Hadoop property `iceberg.mr.catalog.loader.class`.
- If the catalog needs Hadoop configuration, implement
  `org.apache.hadoop.conf.Configurable`.
- Custom `FileIO` (extend `FileIO`, implement `newInputFile`/`newOutputFile`/
  `deleteFile`/`initialize`) can be loaded independently via the `io-impl`
  property on `HadoopCatalog`/`HiveCatalog`.
- Custom `LocationProvider` (where data files get written) can be set
  per-table via the table property `write.location-provider.impl`.
- Encrypted tables impose extra security requirements on custom catalogs —
  see the Iceberg encryption docs.

# Citations

[1] [Catalog properties](https://iceberg.apache.org/docs/latest/catalog-properties)
[2] [Custom Catalog](https://iceberg.apache.org/docs/latest/custom-catalog)
