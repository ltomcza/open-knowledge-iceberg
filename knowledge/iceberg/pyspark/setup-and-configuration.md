---
type: PySpark Guide
title: Setup and Configuration for Iceberg with PySpark
description: Adding the iceberg-spark-runtime package, configuring spark.sql.catalog.* properties, SQL extensions, and catalog-type selection for a PySpark SparkSession.
aliases: [iceberg pyspark setup, spark.sql.catalog, iceberg-spark-runtime, spark.sql.extensions, pyspark --packages iceberg, configure iceberg catalog spark, IcebergSparkSessionExtensions]
tags: [iceberg, pyspark, spark, setup, configuration, catalog]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-configuration
---

# Retrieval Notes

Read this first when setting up any new PySpark + Iceberg environment or
debugging "catalog not found" / "extensions not found" errors. For the deep
reference on individual catalog types (Hive, REST, Glue, JDBC, Nessie,
Hadoop) see `/catalogs/` (per-catalog concepts owned by another part of this
bundle). For DDL/read/write syntax once the session is configured, see
`/pyspark/ddl-create-alter-tables.md`, `/pyspark/reading-data-and-queries.md`,
and `/pyspark/writing-data.md`.

# Summary

- Add the Iceberg Spark runtime via `--packages
  org.apache.iceberg:iceberg-spark-runtime-<spark-version>_<scala-version>:<iceberg-version>`
  at launch (spark-shell/pyspark/spark-submit), or drop the jar into Spark's
  `jars/` folder. Current example: `iceberg-spark-runtime-4.1_2.13:1.11.0`.
- Every Iceberg catalog is declared with Spark properties under
  `spark.sql.catalog.<catalog-name>`, set to
  `org.apache.iceberg.spark.SparkCatalog` (Iceberg-only catalog) or
  `org.apache.iceberg.spark.SparkSessionCatalog` (wraps/replaces Spark's
  built-in `spark_catalog` so both Iceberg and non-Iceberg tables work).
- `spark.sql.catalog.<name>.type` selects the catalog implementation:
  `hive`, `hadoop`, `rest`, `glue`, `jdbc`, or `nessie` — or leave unset and
  supply `spark.sql.catalog.<name>.catalog-impl` for a custom catalog.
- `spark.sql.extensions =
  org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions` is
  required to unlock Iceberg-only SQL (`CALL` procedures, `ALTER TABLE ...
  WRITE ORDERED BY`, `MERGE INTO`, etc.) — without it, most DDL/DML still
  runs but stored procedures and some extended DDL will fail.
- Configuration precedence (highest to lowest): DataSource `.option(...)` >
  Spark session config (`spark.conf.set` / `spark-defaults.conf` / `--conf`)
  > Iceberg table properties (`ALTER TABLE ... SET TBLPROPERTIES`) > built-in
  default.
- In PySpark, set catalog/extension properties via `SparkConf`/
  `SparkSession.builder.config(...)` before `getOrCreate()` — they cannot be
  changed on a running session for a new catalog.

# Building a SparkSession in PySpark

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("IcebergExample")
    .config("spark.jars.packages", "org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    # Iceberg-only catalog named "local", backed by a Hadoop (path-based) warehouse
    .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.local.type", "hadoop")
    .config("spark.sql.catalog.local.warehouse", "$PWD/warehouse")
    .getOrCreate()
)
```

Equivalent at launch time (spark-shell / spark-sql / pyspark CLI, or
spark-submit):

```bash
pyspark --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0 \
    --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
    --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
    --conf spark.sql.catalog.local.type=hadoop \
    --conf spark.sql.catalog.local.warehouse=$PWD/warehouse
```

If Iceberg is installed directly into the Spark distribution (jar dropped
into `jars/`), omit `spark.jars.packages` / `--packages`.

# Adding a Catalog

A catalog is created and named by setting
`spark.sql.catalog.<catalog-name>` to an implementation class. Iceberg
supplies two:

| Class | Behavior |
|---|---|
| `org.apache.iceberg.spark.SparkCatalog` | Iceberg-only catalog; backed by Hive Metastore, Hadoop warehouse, REST, Glue, JDBC, or Nessie depending on `.type` |
| `org.apache.iceberg.spark.SparkSessionCatalog` | Wraps Spark's built-in `spark_catalog`; loads Iceberg tables through Iceberg and falls back to the built-in catalog for non-Iceberg (v1/v2) tables |

## Hive Metastore catalog

```python
spark = (
    SparkSession.builder
    .config("spark.sql.catalog.hive_prod", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.hive_prod.type", "hive")
    .config("spark.sql.catalog.hive_prod.uri", "thrift://metastore-host:9083")
    .getOrCreate()
)
```

Omit `.uri` to reuse the URI already configured via `hive.metastore.uris` in
`hive-site.xml`.

## REST catalog

```python
.config("spark.sql.catalog.rest_prod", "org.apache.iceberg.spark.SparkCatalog")
.config("spark.sql.catalog.rest_prod.type", "rest")
.config("spark.sql.catalog.rest_prod.uri", "http://localhost:8080")
```

See `/catalogs/rest-catalog.md` for auth, OAuth2, and multi-tenant details.

## Hadoop (directory/path-based) catalog

```python
.config("spark.sql.catalog.hadoop_prod", "org.apache.iceberg.spark.SparkCatalog")
.config("spark.sql.catalog.hadoop_prod.type", "hadoop")
.config("spark.sql.catalog.hadoop_prod.warehouse", "hdfs://nn:8020/warehouse/path")
```

Note: a Hive-based catalog only loads Iceberg tables — to mix Iceberg and
non-Iceberg tables in the same Hive metastore, use `SparkSessionCatalog`
(below), not a plain `SparkCatalog`.

## Replacing the session catalog (mixed Iceberg + non-Iceberg tables)

```python
.config("spark.sql.catalog.spark_catalog", "org.apache.iceberg.spark.SparkSessionCatalog")
.config("spark.sql.catalog.spark_catalog.type", "hive")
```

This makes `spark_catalog` (Spark's default/built-in catalog) Iceberg-aware:
Iceberg tables route through Iceberg, everything else falls back to the
built-in catalog, using the same Hive Metastore for both. Useful when you
want `spark_catalog` itself — not a separately-named catalog — to serve both
table kinds.

> Note: Spark before 4.2.0 does not support `V2Function` in the session
> catalog (SPARK-54760), so catalog-scoped SQL functions like
> `system.bucket`, `system.days`, `system.iceberg_version` are unavailable
> through `spark_catalog`. Configure a separate `SparkCatalog`-backed catalog
> and call those functions through it instead.

## Custom catalog implementation

```python
.config("spark.sql.catalog.custom_prod", "org.apache.iceberg.spark.SparkCatalog")
.config("spark.sql.catalog.custom_prod.catalog-impl", "com.my.custom.CatalogImpl")
.config("spark.sql.catalog.custom_prod.my-additional-catalog-config", "my-value")
```

`glue`, `jdbc`, and `nessie` catalog types follow the same
`spark.sql.catalog.<name>.type = <type>` pattern with type-specific
properties — see `/catalogs/` for each (glue.md, jdbc.md, nessie.md,
hadoop.md, hive.md, rest-catalog.md).

# Common Catalog Configuration Properties

| Property | Values | Description |
|---|---|---|
| `spark.sql.catalog.<name>.type` | `hive`, `hadoop`, `rest`, `glue`, `jdbc`, `nessie` | Catalog implementation; leave unset if using `catalog-impl` |
| `spark.sql.catalog.<name>.catalog-impl` | class name | Custom Iceberg `Catalog` implementation; required if `.type` is unset |
| `spark.sql.catalog.<name>.io-impl` | class name | Custom `FileIO` implementation |
| `spark.sql.catalog.<name>.metrics-reporter-impl` | class name | Custom `MetricsReporter` implementation |
| `spark.sql.catalog.<name>.default-namespace` | e.g. `default` | Default current namespace for the catalog |
| `spark.sql.catalog.<name>.uri` | `thrift://host:port` / URL | Hive metastore URI or REST catalog URL |
| `spark.sql.catalog.<name>.warehouse` | e.g. `hdfs://nn:8020/warehouse/path` | Base warehouse path |
| `spark.sql.catalog.<name>.cache-enabled` | `true` (default) / `false` | Catalog cache toggle |
| `spark.sql.catalog.<name>.cache.expiration-interval-ms` | `30000` default | Cache entry TTL; `-1` disables expiration, `0` disables caching entirely |
| `spark.sql.catalog.<name>.table-default.<propertyKey>` | | Default table property applied on create unless overridden |
| `spark.sql.catalog.<name>.table-override.<propertyKey>` | | Enforced table property; cannot be overridden by users |
| `spark.sql.catalog.<name>.view-default.<propertyKey>` / `.view-override.<propertyKey>` | | Same, for views |
| `spark.sql.catalog.<name>.use-nullable-query-schema` | `true` (default) / `false` | Whether CTAS/RTAS mark all fields nullable vs preserve nullability (Spark 3.5+) |
| `spark.sql.catalog.<name>.hadoop.*` | | Per-catalog Hadoop config, takes precedence over global `spark.hadoop.*`, affects only that catalog's Iceberg tables |

More properties: `/catalogs/catalog-properties.md` (common catalog
properties reference).

# Using Catalogs Once Configured

```python
spark.sql("SELECT * FROM hive_prod.db.table")   # explicit 3-part name

spark.sql("USE hive_prod.db")
spark.sql("SELECT * FROM table")                 # current catalog/namespace implied

spark.sql("SHOW CURRENT NAMESPACE").show()
```

Set a default catalog so bare table names resolve without a prefix:

```python
.config("spark.sql.defaultCatalog", "local")
```

# SQL Extensions

Iceberg's extension module adds Iceberg-only SQL syntax (`CALL` for stored
procedures, `ALTER TABLE ... WRITE ORDERED BY`, row-level `MERGE INTO`,
etc). Required property:

| Spark property | Value |
|---|---|
| `spark.sql.extensions` | `org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions` |

# Runtime Configuration

## Precedence (highest wins)

1. DataSource read/write `.option(...)` calls.
2. Spark session config (`spark.conf.set(...)`, `spark-defaults.conf`, `--conf`).
3. Iceberg table properties (`ALTER TABLE ... SET TBLPROPERTIES`).
4. Built-in default.

## Spark SQL options (session-level behavior toggles)

```python
spark = (
    SparkSession.builder
    .appName("IcebergExample")
    .config("spark.sql.catalog.my_catalog", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.iceberg.vectorization.enabled", "false")  # disable vectorized reads
    .getOrCreate()
)
```

| Option | Default | Description |
|---|---|---|
| `spark.sql.iceberg.vectorization.enabled` | table default | Enables vectorized reads of data files |
| `spark.sql.iceberg.check-nullability` | `true` | Validates write schema nullability matches table |
| `spark.sql.iceberg.check-ordering` | `true` | Validates write schema column order matches table |
| `spark.sql.iceberg.planning.preserve-data-grouping` | `false` | Co-locate scan tasks per partition in the same split (storage-partitioned joins) |
| `spark.sql.iceberg.aggregate-push-down.enabled` | `true` | Pushdown of MAX/MIN/COUNT |
| `spark.sql.iceberg.distribution-mode` | see write docs | Distribution strategy during writes |
| `spark.wap.id` / `spark.wap.branch` | `null` | Write-Audit-Publish staging snapshot ID / branch |
| `spark.sql.iceberg.compression-codec` / `-level` / `-strategy` | table default | Write compression overrides |
| `spark.sql.iceberg.data-planning-mode` / `delete-planning-mode` | `AUTO` | Scan planning mode (`AUTO`, `LOCAL`, `DISTRIBUTED`) |
| `spark.sql.iceberg.merge-schema` | `false` | Allows write schema to add missing columns to the table |
| `spark.sql.iceberg.report-column-stats` | `true` | Reports Puffin table stats to Spark's CBO |

(Full list, including executor-cache and variant-shredding options, in the
upstream doc — cited below.)

## Read options (per-DataFrameReader)

```python
spark.read.option("snapshot-id", 10963874102873).table("catalog.db.table")
```

| Option | Default | Description |
|---|---|---|
| `snapshot-id` | latest | Snapshot ID to read |
| `as-of-timestamp` | latest | Millisecond timestamp; reads the snapshot current at that time |
| `split-size` | table property | Overrides `read.split.target-size` / `read.split.metadata-target-size` |
| `lookback` | table property | Overrides `read.split.planning-lookback` |
| `file-open-cost` | table property | Overrides `read.split.open-file-cost` |
| `vectorization-enabled` | table property | Overrides `read.parquet.vectorization.enabled` |
| `batch-size` | table property | Overrides `read.parquet.vectorization.batch-size` |
| `stream-from-timestamp` | none | Streaming: start timestamp in ms |
| `streaming-max-files-per-micro-batch` | `INT_MAX` | Streaming batch size cap (files) |
| `streaming-max-rows-per-micro-batch` | `INT_MAX` | Streaming soft batch size cap (rows) |

Full table in `/pyspark/reading-data-and-queries.md` and
`/pyspark/structured-streaming.md`.

## Write options (per-DataFrameWriterV2)

```python
df.writeTo("catalog.db.table").option("write-format", "avro").option("snapshot-property.key", "value").append()
```

| Option | Default | Description |
|---|---|---|
| `write-format` | table `write.format.default` | `parquet`, `avro`, or `orc` |
| `target-file-size-bytes` | table property | Overrides `write.target-file-size-bytes` |
| `check-nullability` | `true` | Nullable check on fields |
| `snapshot-property.<key>` | null | Adds a custom key/value to the snapshot summary |
| `fanout-enabled` | `false` | Overrides `write.spark.fanout.enabled` |
| `check-ordering` | `true` | Checks input schema matches table column order |
| `isolation-level` | null | `null` (no checks), `serializable`, or `snapshot` — concurrency conflict checking for DataFrame overwrites |
| `validate-from-snapshot-id` | null | Base snapshot ID for isolation-level conflict checks |
| `distribution-mode` | see write docs | Overrides write distribution strategy |
| `delete-granularity` | `file` | Overrides delete granularity for this write |

Full details in `/pyspark/writing-data.md`.

# Citations

[1] [Spark Getting Started](https://iceberg.apache.org/docs/latest/spark-getting-started)
[2] [Spark Quickstart](https://iceberg.apache.org/spark-quickstart)
[3] [Spark Configuration](https://iceberg.apache.org/docs/latest/spark-configuration)
