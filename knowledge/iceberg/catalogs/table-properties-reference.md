---
type: Iceberg Catalog
title: Table Properties Reference
description: Full reference of Iceberg table properties — read, write, encryption, commit-retry/behavior, reserved, informational, and compatibility properties.
aliases: [iceberg table properties, write.format.default, commit.retry, format-version, table configuration, TBLPROPERTIES]
tags: [iceberg, table-properties, configuration, reference]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/configuration
---

# Retrieval Notes

Read this first when looking up a specific **table-level** property (set via
`TBLPROPERTIES`, Spark's `OPTIONS`, or `Table.updateProperties()`) — file
format, compression, commit retry tuning, snapshot retention, format
version, etc. This is distinct from **catalog-level** properties (`uri`,
`warehouse`, auth, ...), which live in
[catalogs-overview.md](/catalogs/catalogs-overview.md) and the per-catalog
concepts. For AWS/S3-specific write behaviors like object-store layout, see
[glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md).

# Summary

- Table properties configure **behavior**, not schema — file format,
  compression, target file sizes, commit retry/backoff, snapshot expiration
  defaults, and encryption.
- `format-version` (default **2** since Iceberg 1.4.0) is a **reserved**
  property: it controls table creation/upgrade behavior but is not persisted
  as an ordinary property in table metadata.
- Row-level operations (delete/update/merge) each have independent
  `<op>.mode` (`copy-on-write` vs `merge-on-read`) and `<op>.isolation-level`
  (`serializable` vs `snapshot`) settings — they do not share one global
  toggle.
- Commit retry behavior (`commit.retry.*`, `commit.status-check.*`) is what
  makes concurrent writers converge instead of failing outright — tune these
  before assuming a catalog "doesn't support concurrency."
- Compression defaults differ by format: Parquet defaults to `zstd`, Avro to
  `gzip`, ORC to `zlib`.
- `write.metadata.delete-after-commit.enabled` + `write.metadata.previous-versions-max`
  control how many old metadata.json files are retained — relevant to
  metadata-file cleanup, distinct from data-file snapshot expiration
  (`history.expire.*`).

# Read properties

| Property | Default | Description |
|---|---|---|
| `read.split.target-size` | 134217728 (128 MB) | Target size when combining data input splits. |
| `read.split.metadata-target-size` | 33554432 (32 MB) | Target size when combining metadata input splits. |
| `read.split.planning-lookback` | 10 | Number of bins to consider when combining input splits. |
| `read.split.open-file-cost` | 4194304 (4 MB) | Estimated cost to open a file, used as a minimum weight when combining splits. |
| `read.parquet.vectorization.enabled` | true | Controls whether Parquet vectorized reads are used. |
| `read.parquet.vectorization.batch-size` | 5000 | Batch size for Parquet vectorized reads. |
| `read.orc.vectorization.enabled` | false | Controls whether ORC vectorized reads are used. |
| `read.orc.vectorization.batch-size` | 5000 | Batch size for ORC vectorized reads. |

# Write properties

| Property | Default | Description |
|---|---|---|
| `write.format.default` | parquet | Default file format: parquet, avro, or orc. |
| `write.delete.format.default` | data file format | Default delete file format. |
| `write.parquet.row-group-size-bytes` | 134217728 (128 MB) | Parquet row group size. |
| `write.parquet.page-size-bytes` | 1048576 (1 MB) | Parquet page size. |
| `write.parquet.page-version` | v1 | `v1` or `v2` Parquet data page version. |
| `write.parquet.page-row-limit` | 20000 | Parquet page row limit. |
| `write.parquet.dict-size-bytes` | 2097152 (2 MB) | Parquet dictionary page size. |
| `write.parquet.compression-codec` | zstd | zstd, brotli, lz4, gzip, snappy, uncompressed. |
| `write.parquet.compression-level` | null | Parquet compression level. |
| `write.parquet.shred-variants` | false | Write variant columns with shredded Parquet encoding for query performance. |
| `write.parquet.variant-inference-buffer-size` | 100 | Rows buffered for schema inference when variant shredding is enabled. |
| `write.parquet.bloom-filter-enabled.column.col1` | not set | Write a bloom filter for column `col1`. |
| `write.parquet.bloom-filter-max-bytes` | 1048576 (1 MB) | Max bytes for a bloom filter bitset. |
| `write.parquet.bloom-filter-fpp.column.col1` | 0.01 | False positive probability for `col1`'s bloom filter (0 < x < 1). |
| `write.parquet.bloom-filter-ndv.column.col1` | not set | Expected distinct values for `col1`'s bloom filter (> 0). |
| `write.parquet.stats-enabled.column.col1` | not set | Whether to collect Parquet column statistics for `col1`. |
| `write.avro.compression-codec` | gzip | gzip (deflate level 9), zstd, snappy, uncompressed. |
| `write.avro.compression-level` | null | Avro compression level. |
| `write.orc.stripe-size-bytes` | 67108864 (64 MB) | Default ORC stripe size. |
| `write.orc.block-size-bytes` | 268435456 (256 MB) | Default filesystem block size for ORC files. |
| `write.orc.compression-codec` | zlib | zstd, lz4, lzo, zlib, snappy, none. |
| `write.orc.compression-strategy` | speed | speed or compression. |
| `write.orc.bloom.filter.columns` | not set | Comma-separated column names to build a Bloom filter for. |
| `write.orc.bloom.filter.fpp` | 0.05 | Bloom filter false positive probability (0 < x < 1). |
| `write.location-provider.impl` | null | Custom `LocationProvider` implementation class. |
| `write.metadata.compression-codec` | none | `none` or `gzip`. |
| `write.metadata.metrics.max-inferred-column-defaults` | 100 | Max columns for which metrics are collected (pre-order schema traversal). |
| `write.metadata.metrics.default` | truncate(16) | Default metrics mode: none, counts, truncate(length), or full. |
| `write.metadata.metrics.column.col1` | not set | Per-column metrics mode override for `col1`. |
| `write.target-file-size-bytes` | 536870912 (512 MB) | Target size for generated data files. |
| `write.delete.target-file-size-bytes` | 67108864 (64 MB) | Target size for generated delete files. |
| `write.distribution-mode` | engine-specific | none (no shuffle), hash (by partition key), range (by partition/sort key). |
| `write.delete.distribution-mode` | not set | Distribution mode for delete writes. |
| `write.update.distribution-mode` | not set | Distribution mode for update writes. |
| `write.merge.distribution-mode` | not set | Distribution mode for merge writes. |
| `write.wap.enabled` | false | Enables write-audit-publish writes. |
| `write.summary.partition-limit` | 0 | Include partition-level summary stats in snapshot summary if changed-partition count is below this limit. |
| `write.metadata.delete-after-commit.enabled` | false | Delete the oldest tracked metadata.json files after each commit. |
| `write.metadata.previous-versions-max` | 100 | Max previous metadata files to track. |
| `write.spark.fanout.enabled` | false | Enable Spark's fanout writer (no clustering required; uses more memory). |
| `write.object-storage.enabled` | false | Enable object-storage location provider (adds a hash to file paths). |
| `write.object-storage.partitioned-paths` | true | Include partition values in the file path. |
| `write.data.path` | `<table location>/data` | Base location for data files. |
| `write.metadata.path` | `<table location>/metadata` | Base location for metadata files. |
| `write.delete.mode` | copy-on-write | copy-on-write or merge-on-read (v2+). |
| `write.delete.isolation-level` | serializable | serializable or snapshot. |
| `write.update.mode` | copy-on-write | copy-on-write or merge-on-read (v2+). |
| `write.update.isolation-level` | serializable | serializable or snapshot. |
| `write.merge.mode` | copy-on-write | copy-on-write or merge-on-read (v2+). |
| `write.merge.isolation-level` | serializable | serializable or snapshot. |
| `write.delete.granularity` | partition | partition or file — granularity of generated delete files. |

# Encryption properties

| Property | Default | Description |
|---|---|---|
| `encryption.key-id` | not set | ID of the table's master encryption key. |
| `encryption.data-key-length` | 16 (bytes) | Length of data-file encryption keys: 16, 24, or 32 bytes. |

# Table behavior properties (commit retry, manifests, expiration, GC)

| Property | Default | Description |
|---|---|---|
| `commit.retry.num-retries` | 4 | Times to retry a commit before failing. |
| `commit.retry.min-wait-ms` | 100 | Min wait before retrying a commit. |
| `commit.retry.max-wait-ms` | 60000 (1 min) | Max wait before retrying a commit. |
| `commit.retry.total-timeout-ms` | 1800000 (30 min) | Total retry timeout for a commit. |
| `commit.status-check.num-retries` | 3 | Times to check whether a commit succeeded after a lost connection, before failing with unknown state. |
| `commit.status-check.min-wait-ms` | 1000 (1s) | Min wait before retrying a status check. |
| `commit.status-check.max-wait-ms` | 60000 (1 min) | Max wait before retrying a status check. |
| `commit.status-check.total-timeout-ms` | 1800000 (30 min) | Total timeout for the commit status check to succeed. |
| `commit.manifest.target-size-bytes` | 8388608 (8 MB) | Target size when merging manifest files. |
| `commit.manifest.min-count-to-merge` | 100 | Min manifests to accumulate before merging. |
| `commit.manifest-merge.enabled` | true | Automatically merge manifests on writes. |
| `history.expire.max-snapshot-age-ms` | 432000000 (5 days) | Default max snapshot age kept across the table and its branches during expiry. |
| `history.expire.min-snapshots-to-keep` | 1 | Default min snapshots kept per branch during expiry. |
| `history.expire.max-ref-age-ms` | `Long.MAX_VALUE` | Max age for snapshot references other than `main` (which never expires). |
| `gc.enabled` | true | Allows garbage collection (expire snapshots, remove orphan files). |

# Reserved table properties

Only control table creation/update behavior — not persisted as an ordinary
property in table metadata.

| Property | Default | Description |
|---|---|---|
| `format-version` | 2 | Table format version per the [spec](https://iceberg.apache.org/spec/#format-versioning). Default is 2 since Iceberg 1.4.0. |

# Informational properties

Documentation-only; do not affect read/write behavior.

| Property | Default | Description |
|---|---|---|
| `comment` | not set | Table-level description of business meaning and usage. |

# Compatibility flags

| Property | Default | Description |
|---|---|---|
| `compatibility.snapshot-id-inheritance.enabled` | false | Allows committing snapshots without explicit snapshot IDs (always true when format version > 1). |

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — catalog-level
  properties (not table-level), which are configured separately from
  everything in this document.
- [glue-catalog-and-s3.md](/catalogs/glue-catalog-and-s3.md) — S3-specific
  storage properties (`s3.*`) that layer on top of `write.*` behavior here.
- `/tables/branching-and-tagging.md` — how `history.expire.*` interacts with
  branches/tags.

# Citations

[1] [Configuration](https://iceberg.apache.org/docs/latest/configuration)
