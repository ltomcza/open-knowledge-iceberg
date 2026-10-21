# Catalog Fundamentals

* [Iceberg Catalogs Overview](catalogs-overview.md) - What a catalog does (atomic metadata pointer + compare-and-swap), the available implementations, and generic catalog properties shared across them.
* [Table Properties Reference](table-properties-reference.md) - Full reference of table-level (not catalog-level) properties: read, write, encryption, commit-retry, reserved, informational, and compatibility flags.

# Catalog Implementations

* [REST Catalog](rest-catalog.md) - The vendor-neutral REST Catalog protocol: why it's becoming the standard, core concepts/endpoints, and authentication options.
* [Hive Metastore Catalog](hive-catalog.md) - Using Hive Metastore as an Iceberg catalog (HiveCatalog): configuration, HMS locking, limitations vs native catalogs.
* [AWS Glue Catalog and S3FileIO](glue-catalog-and-s3.md) - AWS Glue Data Catalog and DynamoDB catalog options, plus S3FileIO storage configuration.
* [Nessie Catalog](nessie-catalog.md) - Nessie's git-like versioned catalog: catalog-level branches/tags/commits, distinct from Iceberg table-level branching.
* [JDBC Catalog](jdbc-catalog.md) - Backing an Iceberg catalog with a relational database over JDBC: configuration and connection examples.
