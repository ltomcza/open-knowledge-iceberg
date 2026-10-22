---
type: Iceberg Catalog
title: JDBC Catalog
description: Using a relational database (via JDBC) as an Iceberg catalog — configuration properties and connection examples.
aliases: [JdbcCatalog, jdbc catalog, relational database catalog, mysql catalog, postgres catalog, rds jdbc catalog]
tags: [iceberg, catalog, jdbc, relational-database]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/jdbc
---

# Retrieval Notes

Read this first for **backing an Iceberg catalog with an existing relational
database** via JDBC. For using this specifically with AWS RDS/Aurora and IAM
auth, see the RDS section in
[glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md#rds--jdbc-catalog).
For generic catalog properties and catalog selection guidance, see
[catalogs-overview.md](/catalogs/catalogs-overview.md).

# Summary

- `JdbcCatalog` stores Iceberg table/namespace pointers in a table inside a
  relational database, reached over a plain JDBC connection string.
- The backing database **must support atomic transactions** — this is what
  the catalog relies on for atomic Iceberg commits and serializable read
  isolation; there's no separate lock manager to configure, unlike
  `HadoopCatalog`.
- Configuration is deliberately open-ended: only `uri` (the JDBC connection
  string) is catalog-specific; every other connection setting (user,
  password, SSL flags, driver-specific options) is passed through via a
  `jdbc.<property_key>` prefix straight to the JDBC driver.
- Best fit when an organization already operates a relational database
  (Postgres, MySQL, RDS, serverless Aurora) that can be repurposed as a
  lightweight metastore without standing up Hive Metastore or a cloud-native
  catalog service.
- The JDBC driver class must be present at runtime (e.g.
  `com.mysql.cj.jdbc.Driver`) — it is not bundled by Iceberg.

# Configuration

| Property | Default | Description |
|---|---|---|
| `uri` | — | The JDBC connection string, e.g. `jdbc:mysql://host:3306/db`. |
| `jdbc.<property_key>` | — | Any key/value pair passed straight through to configure the JDBC connection (user, password, SSL settings, driver-specific flags). |

Because each database/provider needs different flags, there is no fixed
schema for `jdbc.*` — consult your driver's documentation for supported
connection properties.

# Examples

## Spark (MySQL)

```bash
spark-sql --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.12.0 \
    --conf spark.sql.catalog.my_catalog=org.apache.iceberg.spark.SparkCatalog \
    --conf spark.sql.catalog.my_catalog.warehouse=s3://my-bucket/my/key/prefix \
    --conf spark.sql.catalog.my_catalog.type=jdbc \
    --conf spark.sql.catalog.my_catalog.uri=jdbc:mysql://test.1234567890.us-west-2.rds.amazonaws.com:3306/default \
    --conf spark.sql.catalog.my_catalog.jdbc.verifyServerCertificate=true \
    --conf spark.sql.catalog.my_catalog.jdbc.useSSL=true \
    --conf spark.sql.catalog.my_catalog.jdbc.user=admin \
    --conf spark.sql.catalog.my_catalog.jdbc.password=pass
```

Note `warehouse` here points at S3 for data storage even though the catalog
pointer itself lives in MySQL — the catalog backend and the data storage
backend are independent choices.

## Java API

```java
Class.forName("com.mysql.cj.jdbc.Driver"); // ensure the JDBC driver is on the runtime classpath
Map<String, String> properties = new HashMap<>();
properties.put(CatalogProperties.CATALOG_IMPL, JdbcCatalog.class.getName());
properties.put(CatalogProperties.URI, "jdbc:mysql://localhost:3306/test");
properties.put(JdbcCatalog.PROPERTY_PREFIX + "user", "admin");
properties.put(JdbcCatalog.PROPERTY_PREFIX + "password", "pass");
properties.put(CatalogProperties.WAREHOUSE_LOCATION, "s3://warehouse/path");
Configuration hadoopConf = new Configuration(); // only needed if using HadoopFileIO
JdbcCatalog catalog = CatalogUtil.buildIcebergCatalog("test_jdbc_catalog", properties, hadoopConf);
```

# Using AWS RDS / Aurora

The JDBC catalog works unmodified against AWS RDS or serverless Aurora as
the relational database — just point `uri` at the RDS endpoint. For IAM
database authentication instead of a static password, see AWS's JDBC IAM
auth documentation and the RDS section of
[glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md#rds--jdbc-catalog).
This is the recommended path "if your organization already maintains an
existing relational database in RDS... to manage tables."

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — generic catalog
  properties, catalog selection guidance.
- [hive-catalog.md](/catalogs/hive-catalog.md) — an alternative with more
  complex (HMS lock-based) atomicity versus JDBC's plain DB transactions.
- [glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md) — AWS-native
  alternatives (Glue, DynamoDB) and the RDS-specific JDBC notes.

# Citations

[1] [Iceberg JDBC Integration](https://iceberg.apache.org/docs/latest/jdbc)
