---
type: Iceberg Catalog
title: AWS Glue Catalog and S3FileIO
description: Using AWS Glue Data Catalog as an Iceberg catalog, the DynamoDB catalog alternative, and S3FileIO configuration for storage.
aliases: [GlueCatalog, glue data catalog, S3FileIO, iceberg aws, DynamoDbCatalog, s3 catalog, aws glue iceberg]
tags: [iceberg, catalog, aws, glue, s3, dynamodb]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/aws
---

# Retrieval Notes

Read this first for **AWS-specific catalog options** (Glue, DynamoDB) and
**S3 storage configuration** (`S3FileIO`). For generic catalog properties and
catalog selection guidance, see
[catalogs-overview.md](/catalogs/catalogs-overview.md). For the JDBC catalog
as used with AWS RDS specifically, see
[jdbc-catalog.md](/catalogs/jdbc-catalog.md). For table-level write
properties unrelated to AWS, see
[table-properties-reference.md](/catalogs/table-properties-reference.md).

# Summary

- **Glue Catalog** (`type=glue` or `catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog`)
  stores each Iceberg namespace as a Glue Database and each table as a Glue
  Table, using Glue's built-in **optimistic locking** (a per-table version
  ID) for atomic commits — no separate lock manager needed as long as the
  AWS SDK is >= 2.17.131.
- **DynamoDB Catalog** is an alternative AWS-native catalog backed by a
  single DynamoDB table, useful when you need custom secondary indexes on
  table properties or very high write throughput.
- **DynamoDB Lock Manager** is a *different* thing: it's a lock add-on used
  by `HadoopCatalog`/`HadoopTables` (filesystem-based, no catalog) to get
  atomicity on S3, which lacks native write mutual exclusion.
- `S3FileIO` is the recommended `FileIO` for S3 (over the legacy
  `HadoopFileIO`/S3A filesystem) — it implements progressive multipart
  upload, all 3 S3 server-side encryption modes, access points, access
  grants, dual-stack, acceleration, and tunable retries.
- Which catalog to pick: Glue for existing AWS analytics ecosystem (Athena,
  EMR, Redshift, Lake Formation) and IAM-based access control; DynamoDB for
  higher write throughput and custom property indexing; JDBC/RDS if you
  already run a relational DB for this purpose.

# Enabling the AWS module

The `iceberg-aws` module is bundled with Spark/Flink runtimes (0.11.0+), but
the AWS SDK v2 clients are not — add the `iceberg-aws-bundle` (or individual
Glue/S3/DynamoDB/KMS/STS client packages) plus an HTTP client dependency
at runtime. Since Iceberg 1.12.0 the default is Apache HttpClient 5: if you
supply AWS dependencies yourself, use `software.amazon.awssdk:apache5-client`
instead of `apache-client`. Spark 3.4 runtimes were removed in 1.12.0 — use
the 3.5, 4.0, or 4.1 runtime.

```bash
# Spark
spark-sql --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.12.0,org.apache.iceberg:iceberg-aws-bundle:1.12.0 \
    --conf spark.sql.defaultCatalog=my_catalog \
    --conf spark.sql.catalog.my_catalog=org.apache.iceberg.spark.SparkCatalog \
    --conf spark.sql.catalog.my_catalog.warehouse=s3://my-bucket/my/key/prefix \
    --conf spark.sql.catalog.my_catalog.type=glue \
    --conf spark.sql.catalog.my_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO
```

```sql
-- Flink
CREATE CATALOG my_catalog WITH (
  'type'='iceberg',
  'warehouse'='s3://my-bucket/my/key/prefix',
  'catalog-type'='glue',
  'io-impl'='org.apache.iceberg.aws.s3.S3FileIO'
);
```

```sql
-- Hive
SET iceberg.engine.hive.enabled=true;
SET iceberg.catalog.glue.type=glue;
SET iceberg.catalog.glue.warehouse=s3://my-bucket/my/key/prefix;
CREATE EXTERNAL TABLE database_a.table_a
STORED BY 'org.apache.iceberg.mr.hive.HiveIcebergStorageHandler'
TBLPROPERTIES ('iceberg.catalog'='glue');
```

# Glue Catalog

Load it via `catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog` or
`type=glue`. `warehouse` is required, as with all catalogs, and by default
must be an S3 path (Glue uses `S3FileIO`); switch to `HadoopFileIO` or a
custom `FileIO` via `io-impl` to store elsewhere.

| Property | Default | Description |
|---|---|---|
| `glue.id` | AWS account of the default credential | Glue catalog ID (numeric AWS account ID) to point at a Glue catalog in a different account. |
| `glue.skip-archive` | true | Skip archiving older Glue table versions on update. Setting `false` creates many versions quickly under streaming ingestion. |
| `glue.skip-name-validation` | false | Skip Glue name validation for tables/namespaces; risks downstream incompatibility with non-standard characters. |

**Optimistic locking**: each Glue table has a version ID; Iceberg retries a
commit on version mismatch after refreshing metadata and checking for real
conflicts. Requires AWS SDK >= 2.17.131 — below that version, only an
in-memory lock is used and a
[DynamoDB Lock Manager](#dynamodb-lock-manager) is needed for true atomicity.

**Table location**: default root for `my_ns.my_table` is
`<warehouse>/my_ns.db/my_table`. Override per-namespace via the Glue
database's `locationUri` attribute, or per-table via the `location` table
property / SQL `LOCATION` clause.

# DynamoDB Catalog

Backed by a single DynamoDB table recording both namespace and table
metadata pointers.

| Property | Default | Description |
|---|---|---|
| `dynamodb.table-name` | `iceberg` | Name of the DynamoDB table used by `DynamoDbCatalog`. |

Internal design: partition key is the table/namespace `identifier` (avoids
hot-partition issues from clustering all tables of one namespace together); a
GSI on `namespace` supports listing; a string UUID version column `v` avoids
same-millisecond version collisions; table/namespace properties are
flattened as top-level `p.<property_key>` columns so custom GSIs can be added
on any property (e.g. index by an `owner` property).

# RDS / JDBC Catalog

AWS RDS (or serverless Aurora) can back the [JDBC catalog](/catalogs/jdbc-catalog.md)
directly — see that concept for configuration. For IAM-based DB
authentication with RDS, consult AWS's JDBC IAM auth documentation.

# Which catalog to choose (AWS-specific)

1. Existing Glue / Athena / EMR / Redshift / Lake Formation investment ->
   **Glue**, easiest integration.
2. High read/write throughput (e.g. streaming writes) -> **Glue or
   DynamoDB**, both use optimistic locking.
3. Need IAM-resource-level access control -> **Glue** (tables are IAM
   resources); DynamoDB only supports more complex item-level permissions.
4. Need to query/filter tables by arbitrary property without scanning the
   whole catalog -> **DynamoDB**, via custom secondary indexes on `p.*`.
5. Want DynamoDB's benefits while staying connected to Glue -> enable a
   DynamoDB Stream + Lambda trigger to asynchronously sync into Glue.
6. Already run RDS / Aurora -> **JDBC catalog**, easiest integration.

# DynamoDB Lock Manager

Used by `HadoopCatalog` / `HadoopTables` (filesystem-based, catalog-less
tables) to get atomic commits on storage like S3 that lacks native write
mutual exclusion — this is unrelated to the DynamoDB *Catalog* above.

1. Set `lock-impl` = `org.apache.iceberg.aws.dynamodb.DynamoDbLockManager`.
2. Set `lock.table` = the DynamoDB table name to use (auto-created with
   pay-per-request billing if it doesn't exist).
3. Tune with the generic [lock properties](/catalogs/catalogs-overview.md#lock-catalog-properties)
   (heartbeat interval, timeouts, etc).

# S3FileIO configuration

`S3FileIO` is the recommended `FileIO` for S3 (over `HadoopFileIO`/S3A). It's
loaded via `io-impl=org.apache.iceberg.aws.s3.S3FileIO` and is
`GlueCatalog`'s default. It reads `s3a://`/`s3n://` paths too, easing
migration from S3A.

## Progressive multipart upload

| Property | Default | Description |
|---|---|---|
| `s3.multipart.num-threads` | available processors | Threads for uploading parts (shared across output streams). |
| `s3.multipart.part-size-bytes` | 32MB | Size of a single multipart upload part. |
| `s3.multipart.threshold` | 1.5 | Factor × part size at which to switch from single PUT to multipart upload. |
| `s3.staging-dir` | `java.io.tmpdir` | Directory for temporary files during upload. |

## Server-side encryption

| Property | Default | Description |
|---|---|---|
| `s3.sse.type` | `none` | `none`, `s3` (SSE-S3), `kms` (SSE-KMS), `dsse-kms` (dual-layer SSE-KMS), or `custom` (SSE-C). |
| `s3.sse.key` | `aws/s3` for kms/dsse-kms | KMS key ID/ARN, or base64 AES256 key for `custom`. |
| `s3.sse.md5` | null | Base64 MD5 digest of the symmetric key, required for `custom`. |

## Other S3 features

| Property | Default | Description |
|---|---|---|
| `s3.acl` | null | S3 access control list level. |
| `s3.checksum-enabled` | false | Enable checksum validation for S3 writes. |
| `s3.retry.num-retries` | 5 | Number of S3 operation retries; use 32 for high-throughput workloads to ride out throttling. |
| `s3.retry.min-wait-ms` / `s3.retry.max-wait-ms` | 2s / 20s | Retry backoff bounds. |
| `use-arn-region-enabled` | false | Required `true` for cross-region S3 access points. |
| `s3.access-points.<bucket>` | — | Maps a bucket name to an access-point ARN. |
| `s3.access-grants.enabled` | false | Enable S3 Access Grants (requires the plugin jar). |
| `s3.access-grants.fallback-to-iam` | false | Fall back to the IAM role if Access Grants can't authorize. |
| `s3.delete-enabled` | true | Set `false` to tag-and-retain instead of hard-deleting (pairs with S3 lifecycle policies). |
| `s3.delete.tags.<key>` | — | Tags applied to objects before deletion. |
| `s3.delete.num-threads` | — | Threads used for tagging objects on delete. |
| `s3.write.tags.<key>` | — | Custom tags applied to objects on write. |
| `s3.write.table-tag-enabled` / `s3.write.namespace-tag-enabled` | false | Auto-tag objects with `iceberg.table=<name>` / `iceberg.namespace=<name>`. |
| `s3.dualstack-enabled` | false | Use IPv6-capable dual-stack S3 endpoints. |
| `s3.cross-region-access-enabled` | false | Allow cross-region bucket access (adds first-call latency). |
| `s3.acceleration-enabled` | false | Use S3 Transfer Acceleration. |
| `s3.analytics-accelerator.enabled` | false | Enable the Analytics Accelerator Library for S3 reads. |
| `client.factory` | null | Custom `AwsClientFactory` implementation, e.g. `AssumeRoleAwsClientFactory` for cross-account access. |

### Object store file layout

By default Iceberg uses Hive-style storage layout, which can hit S3 prefix
throttling. Set `write.object-storage.enabled=true` (table property) to use
`ObjectStoreLocationProvider`, which hashes each file path (base2, 20-bit,
split into nested 4-bit directories) after `write.data.path` to spread
objects across S3 prefixes. `write.object-storage.partitioned-paths=false`
omits partition values from the path to shorten keys further.

### HTTP client configuration

| Property | Default | Description |
|---|---|---|
| `http-client.type` | `apache` | `apache` or `urlconnection`. |
| `http-client.proxy-endpoint` | null | Optional proxy endpoint. |
| `http-client.apache.max-connections` | null | Max connections (Apache client). |
| `http-client.apache.tcp-keep-alive-enabled` | disabled | TCP keep-alive (Apache client). |
| `http-client.urlconnection.socket-timeout-ms` | null | Socket timeout (URL Connection client). |

### Cross-account / cross-region access

`AssumeRoleAwsClientFactory` (set via `client.factory`) assumes an IAM role
via STS, then initializes Glue/S3/DynamoDB clients with the resulting
credentials:

| Property | Default | Description |
|---|---|---|
| `client.assume-role.arn` | required | ARN of the role to assume. |
| `client.assume-role.region` | required | Region for all clients except STS. |
| `client.assume-role.external-id` | null | Optional external ID. |
| `client.assume-role.timeout-sec` | 1 hour | Session timeout before re-fetching credentials. |

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — generic catalog
  properties, lock properties, catalog selection.
- [hive-catalog.md](/catalogs/hive-catalog.md) — self-hosted metastore
  alternative to Glue.
- [jdbc-catalog.md](/catalogs/jdbc-catalog.md) — RDS-backed alternative.

# Citations

[1] [Iceberg AWS Integrations](https://iceberg.apache.org/docs/latest/aws)
[2] [Apache Iceberg — Releases (1.12.0: Spark 3.4 removed, Apache HttpClient 5 default)](https://iceberg.apache.org/releases/)
