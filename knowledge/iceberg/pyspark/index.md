# Getting Started

* [Setup and Configuration for Iceberg with PySpark](setup-and-configuration.md) - Adding the iceberg-spark-runtime package, configuring spark.sql.catalog.* properties, SQL extensions, and catalog-type selection for a PySpark SparkSession.

# Schema and Table Management

* [DDL — Create, Alter, and Drop Iceberg Tables in PySpark](ddl-create-alter-tables.md) - CREATE TABLE, CTAS/RTAS, ALTER TABLE (columns, partition fields, sort order, identifier fields, branches/tags), DROP TABLE, and Iceberg views, all via spark.sql(...) in PySpark.

# Reading and Writing Data

* [Reading Data and Queries — Iceberg Tables in PySpark](reading-data-and-queries.md) - Batch reads via spark.table/spark.read, time travel (VERSION AS OF, TIMESTAMP AS OF, snapshot-id/as-of-timestamp/branch/tag options), incremental reads, metadata tables (history, snapshots, files, manifests, partitions, entries), and system.* partition-transform SQL functions.
* [Writing Data to Iceberg Tables in PySpark](writing-data.md) - DataFrame writes via writeTo (append, overwritePartitions, overwrite, create/replace/createOrReplace), INSERT INTO / INSERT OVERWRITE via SQL, dynamic vs static partition overwrite, writing to branches, distribution modes, and file-size control.
* [MERGE INTO, UPDATE, and DELETE — Row-Level Operations in PySpark](merge-into-and-row-level-operations.md) - MERGE INTO (SQL and DataFrame mergeInto) matched/not-matched/not-matched-by-source clauses, UPDATE, DELETE FROM, snapshot summary fields, and upsert/CDC patterns and pitfalls for Iceberg tables in PySpark.
* [Structured Streaming Reads and Writes on Iceberg Tables](structured-streaming.md) - readStream/writeStream options for Iceberg with PySpark Structured Streaming — incremental reads, micro-batch rate limiting, append/complete output modes, fanout writer, and why streaming tables need regular maintenance.

# Operations and Maintenance

* [Spark Stored Procedures Reference — CALL system.* in PySpark](spark-procedures.md) - Exact CALL syntax and named arguments for every Iceberg Spark stored procedure — rollback, snapshot management, expire_snapshots, remove_orphan_files, rewrite_data_files/manifests/position_delete_files, migrate/snapshot/add_files, register_table, changelog views, table statistics, and table-path replication.

# Deployment Modes

* [Using Iceberg Tables Through Spark Connect](spark-connect.md) - Running Iceberg against a Spark Connect server from a thin pyspark-client: why catalog/extension config must be set server-side, connecting with SparkSession.builder.remote(...), and Connect-specific constraints.
