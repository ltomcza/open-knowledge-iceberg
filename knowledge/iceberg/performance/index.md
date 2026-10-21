# Performance

* [Performance Overview](performance-overview.md) - Iceberg's design goals and metadata-based scan planning that makes queries fast at scale.
* [Partitioning Strategy for Performance](partitioning-strategy-for-performance.md) - Choosing partition granularity, avoiding over/under-partitioning, and using partition evolution.
* [Sort Order and File Layout](sort-order-and-file-layout.md) - How sort order and z-order clustering improve min/max stat-based file pruning.
* [Read/Write Performance Tuning (Spark)](read-write-performance-tuning.md) - Spark-side tuning: vectorized reads, split sizing, fanout writers, shuffle partitions.
* [Large-Scale MERGE / UPDATE Tuning (Spark)](large-scale-merge-and-update-tuning.md) - Making MERGE/UPDATE/DELETE fast on billion-row tables: COW vs MOR, ON-clause pushdown, bounded merges, join strategy, distribution modes, delete granularity, v3 deletion vectors.
* [Storage-Partitioned Joins (SPJ)](storage-partitioned-joins.md) - Shuffle-free joins and MERGE between identically partitioned Iceberg tables: requirements, Spark configs, query shape, verification.
* [High-Volume Table Playbook](high-volume-table-playbook.md) - Design and tuning profile for tables ingesting hundreds of millions of rows/day: layout, file/Parquet/bloom settings, metadata, planning, daily schedule.
* [Metrics and Monitoring](metrics-and-monitoring.md) - Iceberg's MetricsReporter interface for scan and commit observability.
