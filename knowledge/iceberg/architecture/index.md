# Core Architecture

* [Apache Iceberg Table Format — Overview](table-format-overview.md) - What Iceberg is, why it exists vs. Hive tables, and the layered catalog → metadata.json → manifest list → manifest → data file architecture.
* [Iceberg Metadata Layer — metadata.json](metadata-layer.md) - Deep dive on metadata.json structure: table UUID, format-version differences (v1/v2/v3), schemas, partition specs, sort orders, snapshot-log, metadata-log.
* [Manifests and Manifest Lists](manifests-and-manifest-lists.md) - Manifest list vs. manifest file structure, sequence numbers, data vs. delete manifests, and partition summaries used for pruning.
* [Snapshots and Versioning](snapshots-and-versioning.md) - Snapshot structure, snapshot log, parent-child snapshot lineage, and how a write atomically produces a new snapshot.
* [Reliability and Concurrency](reliability-and-concurrency.md) - ACID guarantees, serializable snapshot isolation, optimistic concurrency control, and concurrent-writer conflict resolution.

# Schema and Partitioning

* [Schema Evolution](schema-evolution.md) - Safe schema changes (add/drop/rename/reorder/widen), permanent column IDs, and how this differs from Hive/Parquet evolution.
* [Partitioning and Hidden Partitioning](partitioning-and-hidden-partitioning.md) - Hidden partitioning concept, partition spec structure, and partition evolution without rewriting data.
* [Partition Transforms Reference](partition-transforms-reference.md) - Full reference table of transforms (identity, bucket[N], truncate[W], year, month, day, hour, void) with semantics and use cases.

# Table Lifecycle Features

* [Branching and Tagging](branching-and-tagging.md) - Branches vs. tags as named snapshot references, the write-audit-publish (WAP) pattern, and retention properties.
* [Row-Level Deletes](row-level-deletes.md) - Copy-on-write vs. merge-on-read, position deletes vs. equality deletes vs. deletion vectors, and delete-file structure.

# Storage and Security

* [FileIO and Table Encryption](file-io-and-encryption.md) - The FileIO storage abstraction and an overview of Iceberg's native table encryption (KMS integration, envelope encryption).

# Reference

* [Iceberg Glossary](glossary.md) - Quick-lookup definitions of key Iceberg terms for fast reference.
