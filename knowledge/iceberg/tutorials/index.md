Start here if you're new to Apache Iceberg and want to learn it hands-on rather than read reference
material first. This is a **numbered, narrative learning path** — follow it top to bottom, pasting each
code block into a terminal, `pyspark` shell, notebook cell, or VS Code task as you go. Tutorial 1 builds
a small, disposable Docker image with PySpark and Iceberg pre-installed and wires it up to VS Code tasks
for running and debugging scripts; every tutorial from there on uses that same environment, a local
filesystem catalog writing to a fixed warehouse path, so nothing here requires a Hive Metastore or any
cloud account — you need Docker and VS Code, but no Java or Python installed on your host at all. (The
only exception is tutorial 8, which is pure Python and doesn't need Spark/Java either way.) If you
already know Iceberg's concepts and just need exact syntax, the sibling directories (`/architecture/`,
`/pyspark/`, `/catalogs/`, `/maintenance/`, `/pyiceberg/`) are dense, retrieval-optimized references
instead — each tutorial links out to the relevant reference pages for readers who want to go deeper on
"why", not just "how".

# The Learning Path

1. [1. Environment Setup](01-environment-setup.md) - Build a Docker image with PySpark and Iceberg pre-installed, and drive it from VS Code tasks to build, run, and debug scripts — the one-time setup every later tutorial builds on.
2. [2. Your First Table: Create, Insert, Read](02-first-table-crud.md) - Create a table, write it with both SQL and a PySpark DataFrame, read it back, and see the actual metadata/data files Iceberg wrote to disk.
3. [3. Schema and Partition Evolution](03-schema-and-partition-evolution.md) - Add and rename a column, then change a populated table's partitioning and prove old files are left untouched.
4. [4. Time Travel and Rollback](04-time-travel-and-rollback.md) - List a table's snapshot history, query an earlier state with `VERSION AS OF`/`TIMESTAMP AS OF`, and roll back for real with a stored procedure.
5. [5. Upsert, MERGE INTO, and CDC](05-upsert-merge-and-cdc.md) - Apply a batch of updates, inserts, and deletes from a staging DataFrame to a target table in one atomic `MERGE INTO`.
6. [6. Compaction and Maintenance](06-compaction-and-maintenance.md) - Deliberately create a small-files problem, then fix it with `rewrite_data_files`, `expire_snapshots`, and `remove_orphan_files`.
7. [7. Structured Streaming into Iceberg](07-structured-streaming-into-iceberg.md) - Stream from Spark's built-in `rate` source into an Iceberg table and read it back as a second streaming query — no Kafka needed.
8. [8. PyIceberg Quickstart (No Spark)](08-pyiceberg-quickstart-no-spark.md) - Repeat the create/write/read journey using pure Python PyIceberg — no JVM, no SparkSession — and learn when to reach for it instead of Spark.
9. [9. Iceberg Through Spark Connect](09-spark-connect.md) - Start an Iceberg-enabled Spark Connect server and drive it from a separate, thin pyspark-client environment over gRPC — the same table operations from tutorial 2, decoupled from the driver.
