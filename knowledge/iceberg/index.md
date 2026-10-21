---
okf_version: "0.1"
---

# Apache Iceberg Knowledge Bundle

A knowledge base for becoming genuinely proficient with Apache Iceberg and its
PySpark / Python ecosystem — how the table format works internally, how to use
it day to day from PySpark and PyIceberg, and how to run it well in production
(maintenance, performance tuning). Built from the official Apache Iceberg and
PyIceberg documentation.

**New to Iceberg?** Start with the [tutorials](tutorials/index.md) — a
hands-on, numbered learning path you run on your own laptop. **Already know
the concepts and just need exact syntax or a mechanism explained?** Jump
straight into the reference sections below; each is optimized for fast
lookup, not linear reading.

# Start Here

* [Tutorials](tutorials/index.md) - Numbered, runnable, step-by-step walkthroughs from "hello world" table through streaming, maintenance, and PyIceberg — no Docker or cloud account required.
* [Cheat Sheet](cheat-sheet.md) - A three-part, memorize-this condensation of the whole bundle: architecture mental model, PySpark day-to-day syntax, and production maintenance/performance rules.

# How Iceberg Works

* [Architecture](architecture/index.md) - The table format itself: metadata.json, manifests, snapshots, schema/partition evolution, ACID guarantees, branching/tagging, row-level deletes, storage, and a glossary.

# Catalogs

* [Catalogs](catalogs/index.md) - What a catalog does and how to configure every major implementation: REST, Hive Metastore, AWS Glue/S3, Nessie, JDBC, plus the full table-properties reference.

# Using Iceberg from PySpark

* [PySpark Guide](pyspark/index.md) - Setup, DDL, reads/time-travel, writes, MERGE INTO/upserts, the full `CALL system.*` stored-procedure reference, and structured streaming.

# Using Iceberg from Python (no Spark)

* [PyIceberg Guide](pyiceberg/index.md) - The pure-Python, JVM-free Iceberg implementation: catalog config, reading, writing/upsert, schema/partition evolution, filter expressions, CLI, and maintenance.

# Running Iceberg in Production

* [Maintenance](maintenance/index.md) - Compaction, snapshot expiration, orphan-file removal, manifest rewriting, a post-update maintenance runbook, and recommended scheduling.
* [Performance](performance/index.md) - Partitioning strategy, sort order/z-order, Spark read/write tuning knobs, large-scale MERGE/UPDATE tuning, storage-partitioned joins, a high-volume table playbook, and metrics/monitoring.

# Suggested Reading Order

1. [Tutorials 1-2](tutorials/01-environment-setup.md) to get a working environment and your first table.
2. [Architecture: Table Format Overview](architecture/table-format-overview.md) to understand what's actually happening under the hood.
3. Work through the [rest of the tutorials](tutorials/index.md) for schema/partition evolution, time travel, upserts, streaming, maintenance, PyIceberg, and Spark Connect.
4. Use the [PySpark](pyspark/index.md), [Catalogs](catalogs/index.md), [Maintenance](maintenance/index.md), and [Performance](performance/index.md) sections as ongoing references once you're building real pipelines.
5. Reach for [PyIceberg](pyiceberg/index.md) when you need lightweight, JVM-free table access (e.g. from a script, notebook, or orchestrator that shouldn't spin up Spark).
