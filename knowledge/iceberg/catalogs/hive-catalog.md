---
type: Iceberg Catalog
title: Hive Metastore Catalog
description: Using the Hive Metastore as an Iceberg catalog (HiveCatalog) — configuration, locking behavior, and limitations versus native catalogs.
aliases: [HiveCatalog, hive metastore catalog, HMS catalog, iceberg.engine.hive.enabled, thrift metastore]
tags: [iceberg, catalog, hive, hive-metastore, locking]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/hive
---

# Retrieval Notes

Read this first for **using an existing Hive Metastore (HMS) as an Iceberg
catalog** — `type=hive` / `HiveCatalog`. This is about HMS as a *catalog
backend* for any engine (Spark, Flink, Trino), not only about querying
Iceberg tables from the Hive query engine itself (though DDL/DML examples
below use Hive SQL for illustration). For catalog selection tradeoffs, see
[catalogs-overview.md](/catalogs/catalogs-overview.md). For generic locking
properties shared with other catalogs, see
[catalogs-overview.md#lock-catalog-properties](/catalogs/catalogs-overview.md).

# Summary

- `HiveCatalog` stores each Iceberg table as a Hive Metastore table entry
  whose properties point at the table's current `metadata.json` location —
  HMS is used purely as a pointer store, not for HMS-native partition
  tracking.
- Supported with Hive Metastore versions 2.3.10+ or 3.1.3+.
- Atomic commits are guaranteed via **HMS locking**, a two-step
  create-lock-then-check-lock process; this is the mechanism that gives
  `HiveCatalog` its compare-and-swap guarantee.
- Core config is just the generic catalog properties — `type=hive`, `uri`
  (thrift metastore URI), `warehouse`, `clients` — no Hive-specific
  properties are required to get a working catalog.
- Limitation vs. native/REST catalogs: from the Hive **engine's**
  perspective there is only one global catalog per Hadoop configuration by
  default; multiple Iceberg catalogs must be registered explicitly via
  `iceberg.catalog.<name>.*` Hadoop properties to be queryable from Hive SQL.
- HMS lock timing properties must stay below the Hive Metastore's own
  transaction timeout (`hive.txn.timeout`), or heartbeats can expire mid-lock
  and cause spurious lock loss.

# Configuration

## Generic catalog properties (Spark example)

```
spark.sql.catalog.hive_prod = org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.hive_prod.type = hive
spark.sql.catalog.hive_prod.uri = thrift://metastore-host:port
# omit uri to use the same URI Spark itself uses: hive.metastore.uris in hive-site.xml
```

| Property | Description |
|---|---|
| `type` | `hive` selects `HiveCatalog`. |
| `uri` | Hive metastore thrift URI, e.g. `thrift://host:9083`. |
| `warehouse` | Root warehouse path for new tables. |
| `clients` | Hive client pool size at the generic catalog-properties level (default 2). |

The Hive-based catalog only loads Iceberg tables; to load non-Iceberg tables
from the same metastore in the same Spark session, use a session catalog
wrapper (`SparkSessionCatalog`) instead of `SparkCatalog`.

## HMS lock and client-pool properties

| Property | Default | Description |
|---|---|---|
| `iceberg.hive.client-pool-size` | 5 | Size of the Hive client pool used when tracking tables in HMS. |
| `iceberg.hive.lock-creation-timeout-ms` | 180000 (3 min) | Max time to create a lock in HMS. |
| `iceberg.hive.lock-creation-min-wait-ms` | 50 | Min time between retries creating the HMS lock. |
| `iceberg.hive.lock-creation-max-wait-ms` | 5000 | Max time between retries creating the HMS lock. |
| `iceberg.hive.lock-timeout-ms` | 180000 (3 min) | Max time to acquire a lock. |
| `iceberg.hive.lock-check-min-wait-ms` | 50 | Min time between checks of lock acquisition. |
| `iceberg.hive.lock-check-max-wait-ms` | 5000 | Max time between checks of lock acquisition. |
| `iceberg.hive.lock-heartbeat-interval-ms` | 240000 (4 min) | Heartbeat interval for HMS locks. |
| `iceberg.hive.metadata-refresh-max-retries` | 2 | Max retries when the metadata file is missing. |
| `iceberg.hive.table-level-lock-evict-ms` | 600000 (10 min) | JVM table lock timeout. |
| `iceberg.engine.hive.lock-enabled` | true | Whether HMS locks are used to ensure commit atomicity. |

**Warning:** `iceberg.hive.lock-check-max-wait-ms` and
`iceberg.hive.lock-heartbeat-interval-ms` must be less than the Hive
Metastore's own transaction timeout (`hive.txn.timeout` /
`metastore.txn.timeout`), or heartbeats can expire in HMS before Iceberg
retries the lock check.

**Danger:** setting `iceberg.engine.hive.lock-enabled=false` disables HMS
locks for commits and **risks table corruption** unless *all* of the
following hold: the HMS server has HIVE-26882 (and HIVE-28121 if backed by
MySQL/MariaDB), every `HiveCatalog` writer touching the table is on Iceberg
1.3+, and every one of them has also disabled locks. Even with the global
flag disabled, per-table locking can be re-enabled via the table property
`engine.hive.lock-enabled=true`.

# Registering multiple / custom catalogs for the Hive query engine

The Hive **engine** (as opposed to `HiveCatalog` used by other engines) only
sees one catalog by default. A table in HMS can represent an Iceberg table
three ways, controlled by its `iceberg.catalog` table property:

1. Unset — loaded via the `HiveCatalog` for the metastore configured in the
   Hive environment.
2. Set to a registered catalog name — loaded via that custom catalog.
3. Set to `location_based_table` — loaded directly from the table's root
   filesystem location (no catalog).

Register additional catalogs globally via Hadoop configuration:

```
SET iceberg.catalog.<catalog_name>.type=hive|hadoop;      -- or omit for a custom catalog
SET iceberg.catalog.<catalog_name>.catalog-impl=...;      -- required if type is unset
SET iceberg.catalog.<catalog_name>.<key>=<value>;         -- any other catalog property
```

Examples:

```sql
-- Register a second HiveCatalog
SET iceberg.catalog.another_hive.type=hive;
SET iceberg.catalog.another_hive.uri=thrift://example.com:9083;
SET iceberg.catalog.another_hive.clients=10;
SET iceberg.catalog.another_hive.warehouse=hdfs://example.com:8020/warehouse;

-- Register a HadoopCatalog
SET iceberg.catalog.hadoop.type=hadoop;
SET iceberg.catalog.hadoop.warehouse=hdfs://example.com:8020/warehouse;

-- Register an AWS GlueCatalog
SET iceberg.catalog.glue.type=glue;
SET iceberg.catalog.glue.warehouse=s3://my-bucket/my/key/prefix;
SET iceberg.catalog.glue.lock.table=myGlueLockTable;
```

Then overlay a Hive table onto a table in a custom catalog:

```sql
CREATE EXTERNAL TABLE database_a.table_a
STORED BY 'org.apache.iceberg.mr.hive.HiveIcebergStorageHandler'
TBLPROPERTIES ('iceberg.catalog'='hadoop_cat');
```

# Enabling Iceberg support in Hive (the query engine)

Since Iceberg 1.8.0 there is no separate Hive runtime connector release; use
Hive 4.0.0+ (embedded Iceberg integration) or the Hive runtime connector
bundled with Iceberg 1.6.1 for Hive 2.x/3.x. Hive 4.0.x ships with Iceberg
1.4.3 embedded; Hive 4.1.x/4.2.x ship with Iceberg 1.9.1.

To avoid surfacing broken tables, Hive won't attach the Iceberg storage
handler to a table unless support is explicitly enabled:

- **Globally**: `iceberg.engine.hive.enabled=true` in Hadoop configuration
  (e.g. in `hive-site.xml`).
- **Per table**: table property `engine.hive.enabled=true`, which overrides
  the global setting.

Note: DML operations (INSERT/UPDATE/DELETE/MERGE) require the **Tez**
execution engine.

# Limitations vs. native/REST catalogs

- Locking is a two-phase HMS-side process (create then check) with several
  tunable timeouts — more moving parts than an atomic RDBMS transaction
  (JDBC catalog) or a REST server's server-side deconfliction.
- Table property sync between Iceberg and HMS TBLPROPERTIES is
  **HiveCatalog-only** — not available for other catalog implementations.
- The Hive query engine itself has a single implicit catalog unless
  additional catalogs are registered via Hadoop config, which is more manual
  than a REST catalog's config-endpoint-driven discovery.
- Requires operating and scaling a Hive Metastore service (typically backed
  by its own RDBMS) as infrastructure, versus e.g. a managed catalog like
  AWS Glue.

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — generic catalog
  properties and lock properties.
- [glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md) — a
  managed-service alternative to self-hosting HMS.
- [jdbc-catalog.md](/catalogs/jdbc-catalog.md) — an RDBMS-backed catalog with
  simpler transactional locking than HMS.

# Citations

[1] [Hive](https://iceberg.apache.org/docs/latest/hive)
[2] [Catalog properties — Hive Metastore Configuration](https://iceberg.apache.org/docs/latest/catalog-properties)
[3] [Spark Configuration — catalog configuration](https://iceberg.apache.org/docs/latest/spark-configuration)
