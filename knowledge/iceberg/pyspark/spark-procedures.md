---
type: PySpark Guide
title: Spark Stored Procedures Reference — CALL system.* in PySpark
description: Exact CALL syntax and named arguments for every Iceberg Spark stored procedure — rollback, snapshot management, expire_snapshots, remove_orphan_files, rewrite_data_files/manifests/position_delete_files, migrate/snapshot/add_files, register_table, changelog views, table statistics, and table-path replication.
aliases: [CALL system.rewrite_data_files, CALL system.expire_snapshots, iceberg spark procedures, rollback_to_snapshot, remove_orphan_files, migrate table to iceberg, add_files procedure, create_changelog_view, rewrite_manifests, compute_table_stats]
tags: [iceberg, pyspark, spark, procedures, maintenance, migration, cdc]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-procedures
---

# Retrieval Notes

**This file is the exact `CALL` syntax reference.** For maintenance
strategy/scheduling guidance (which procedures to run, how often, in what
order) see `/maintenance/maintenance-scheduling-and-strategy.md`. For the
underlying concepts of compaction and file sizing see
`/maintenance/compaction-and-file-sizing.md`. For branches/tags DDL
referenced by several snapshot-management procedures see
`/pyspark/ddl-create-alter-tables.md`. For time travel and metadata table
querying (an alternative way to inspect snapshots) see
`/pyspark/reading-data-and-queries.md`.

# Summary

- All procedures live in the `system` namespace of a configured Iceberg
  catalog: `CALL catalog_name.system.procedure_name(...)`.
- Spark 3.x: procedures require Iceberg SQL extensions
  (`IcebergSparkSessionExtensions`). Spark 4.0+: supported natively without
  extensions, but procedure names become **case-sensitive**.
- Arguments can be passed **by name** (recommended, any order, optional
  args may be omitted) or **by position** (only trailing optional args may
  be omitted) — never mix the two styles in one call.
- Named-argument call: `CALL catalog_name.system.procedure_name(arg_name_2
  => arg_2, arg_name_1 => arg_1)`.
- Categories covered below: snapshot management (rollback, cherry-pick,
  publish, fast-forward), metadata management / maintenance
  (`expire_snapshots`, `remove_orphan_files`, `rewrite_data_files`,
  `rewrite_manifests`, `rewrite_position_delete_files`), table migration
  (`snapshot`, `migrate`, `add_files`, `register_table`), metadata
  information (`ancestors_of`), change data capture
  (`create_changelog_view`), table/partition statistics, and table-path
  replication (`rewrite_table_path`).

# Usage

```python
# named arguments (recommended)
spark.sql("CALL catalog_name.system.procedure_name(arg_name_2 => 'arg_2', arg_name_1 => 'arg_1')")

# positional arguments — only trailing optional args may be omitted
spark.sql("CALL catalog_name.system.procedure_name(arg_1, arg_2)")
```

# Snapshot Management

| Procedure | Required args | Optional args | Purpose |
|---|---|---|---|
| `rollback_to_snapshot` | `table` string, `snapshot_id` long | — | Roll back a table to a specific snapshot ID |
| `rollback_to_timestamp` | `table` string, `timestamp` timestamp | — | Roll back to the snapshot current at a given time |
| `set_current_snapshot` | `table` string | `snapshot_id` long **or** `ref` string (exactly one) | Point current snapshot at any snapshot/branch/tag — not required to be an ancestor |
| `cherrypick_snapshot` | `table` string, `snapshot_id` long | — | Apply an append/dynamic-overwrite snapshot's changes as a new snapshot, without altering the original |
| `publish_changes` | `table` string, `wap_id` string | — | Publish a staged Write-Audit-Publish snapshot into the table; fails if multiple snapshots share the `wap_id` |
| `fast_forward` | `table` string, `branch` string, `to` string | — | Fast-forward one branch's current snapshot to another branch's latest |

All of the above (except `fast_forward`) **invalidate all cached Spark
plans** referencing the affected table.

```python
spark.sql("CALL catalog_name.system.rollback_to_snapshot('db.sample', 1)")

spark.sql("CALL catalog_name.system.rollback_to_timestamp('db.sample', TIMESTAMP '2021-06-30 00:00:00.000')")

spark.sql("CALL catalog_name.system.set_current_snapshot('db.sample', 1)")
spark.sql("CALL catalog_name.system.set_current_snapshot(table => 'db.sample', ref => 's1')")

spark.sql("CALL catalog_name.system.cherrypick_snapshot('my_table', 1)")
spark.sql("CALL catalog_name.system.cherrypick_snapshot(snapshot_id => 1, table => 'my_table')")

spark.sql("CALL catalog_name.system.publish_changes('my_table', 'wap_id_1')")
spark.sql("CALL catalog_name.system.publish_changes(wap_id => 'wap_id_2', table => 'my_table')")

spark.sql("CALL catalog_name.system.fast_forward('my_table', 'main', 'audit-branch')")
```

`rollback_to_snapshot`/`rollback_to_timestamp` return
(`previous_snapshot_id`, `current_snapshot_id`); `cherrypick_snapshot` and
`publish_changes` return (`source_snapshot_id`, `current_snapshot_id`);
`fast_forward` returns (`branch_updated`, `previous_ref`, `updated_ref`).

# Metadata Management (Maintenance Procedures)

## `expire_snapshots`

Removes old snapshots and any data/delete/manifest files uniquely owned by
them (never removes files still needed by a live snapshot).

| Argument | Required | Type | Default / notes |
|---|---|---|---|
| `table` | yes | string | |
| `older_than` | no | timestamp | 5 days ago |
| `retain_last` | no | int | 1 (ancestor snapshots always preserved regardless of `older_than`) |
| `max_concurrent_deletes` | no | int | no thread pool by default |
| `stream_results` | no | boolean | false — set `true` to stream deletion file list to the driver by RDD partition and avoid driver OOM on large tables |
| `snapshot_ids` | no | array of long | specific snapshot IDs to expire |
| `clean_expired_metadata` | no | boolean | also clean up partition specs/schemas no longer referenced |

If `older_than`/`retain_last` are omitted, the table's own expiration
properties apply. Snapshots referenced by a branch or tag are never
expired by this call; branch/tag retention is controlled separately by
`history.expire.max-ref-age-ms` (`main` never expires).

```python
spark.sql("""
CALL hive_prod.system.expire_snapshots('db.sample', TIMESTAMP '2021-06-30 00:00:00.000', 100)
""")  # older than the timestamp, but always keep the last 100 snapshots

spark.sql("""
CALL hive_prod.system.expire_snapshots(table => 'db.sample', snapshot_ids => ARRAY(123))
""")  # expire a specific (non-current) snapshot
```

Output: `deleted_data_files_count`, `deleted_position_delete_files_count`,
`deleted_equality_delete_files_count`, `deleted_manifest_files_count`,
`deleted_manifest_lists_count`, `deleted_statistics_files_count`.

## `remove_orphan_files`

Removes files present on storage but not referenced by any table metadata.

| Argument | Required | Type | Default / notes |
|---|---|---|---|
| `table` | yes | string | |
| `older_than` | no | timestamp | 3 days ago |
| `location` | no | string | table location |
| `dry_run` | no | boolean | false |
| `max_concurrent_deletes` | no | int | no thread pool |
| `stream_results` | no | boolean | false; recommended `true` to avoid driver OOM (caps sampled output at 20,000 paths) |
| `file_list_view` | no | string | pre-built dataset/view of files to check, skips directory listing |
| `equal_schemes` | no | map | schemes to treat as equal, default `map('s3a,s3n','s3')` |
| `equal_authorities` | no | map | authorities to treat as equal |
| `prefix_mismatch_mode` | no | string | `ERROR` (default) / `IGNORE` / `DELETE` |
| `prefix_listing` | no | boolean | false; use prefix-based listing (`SupportsPrefixOperations`) if the table's FileIO supports it |

```python
# dry run first
spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', dry_run => true)")

spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', location => 'tablelocation/data')")

spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', file_list_view => 'files_view')")

spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', prefix_mismatch_mode => 'IGNORE')")
spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', prefix_mismatch_mode => 'DELETE')")

spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', equal_schemes => map('file', 'file1'))")
spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', equal_authorities => map('ns1', 'ns2'))")

spark.sql("CALL catalog_name.system.remove_orphan_files(table => 'db.sample', prefix_listing => true)")
```

Output: `orphan_file_location` (one row per orphan file found/removed).

## `rewrite_data_files`

Bin-packs or sorts small/large data files into files closer to
`write.target-file-size-bytes`.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | |
| `strategy` | no | string | `binpack` (default) or `sort` |
| `sort_order` | no | string | `zorder(c1,c2,c3)`, `hilbert(c1,c2,c3)` (Spark 4.1, Iceberg 1.12+), **or** comma-separated `ColumnName ASC\|DESC NULLS FIRST\|LAST`; defaults to table's sort order. `zorder`/`hilbert` can't be combined with each other or with plain columns |
| `options` | no | map | see general options table below |
| `where` | no | string | filter predicate; all files that may contain matching data are selected |

### General options (map key/value strings)

| Key | Default | Meaning |
|---|---|---|
| `max-concurrent-file-group-rewrites` | 5 | Max file groups rewritten simultaneously |
| `partial-progress.enabled` | false | Commit groups incrementally instead of one big commit |
| `partial-progress.max-commits` | 10 | Max commits allowed under partial progress |
| `partial-progress.max-failed-commits` | = max-commits | Max failed commits tolerated under partial progress |
| `use-starting-sequence-number` | true | Use the compaction-start sequence number, not the new snapshot's |
| `rewrite-job-order` | none | `bytes-asc`/`bytes-desc`/`files-asc`/`files-desc`/`none` |
| `target-file-size-bytes` | 536870912 (512MB, from `write.target-file-size-bytes`) | Target output file size |
| `min-file-size-bytes` | 75% of target | Below this, always a rewrite candidate |
| `max-file-size-bytes` | 180% of target | Above this, always a rewrite candidate |
| `min-input-files` | 5 | File-group size that forces a rewrite regardless of other criteria |
| `rewrite-all` | false | Force rewrite of all provided files |
| `max-file-group-size-bytes` | 107374182400 (100GB) | Max bytes rewritten per file group (splits huge partitions) |
| `delete-file-threshold` | 2147483647 | Min delete count on a data file to trigger rewrite |
| `delete-ratio-threshold` | 0.3 | Min deletion ratio to trigger rewrite |
| `output-spec-id` | current spec id | Partition spec to align rewritten output to |
| `remove-dangling-deletes` | false | Also drop delete files that no longer apply to any live data file (extra commit) |
| `max-files-to-rewrite` | null (all) | Upper limit on files rewritten in this call |
| `max-file-group-input-files` | Long.MAX_VALUE | Max input files per file group (1.12+) |
| `cache-delete-files` | false | Use the executor cache for delete files during the rewrite (1.12+; helps when one delete file applies to many data files) |

Sort-strategy-only options: `compression-factor` (default `1.0`, adjusts
estimated output file count vs on-disk size), `shuffle-partitions-per-file`
(default `1`). Zorder-only: `var-length-contribution` (default `8` bytes),
`max-output-size` (default `2147483647`).

```python
# default bin-pack
spark.sql("CALL catalog_name.system.rewrite_data_files('db.sample')")

# sort strategy
spark.sql("""
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample', strategy => 'sort',
  sort_order => 'id DESC NULLS LAST,name ASC NULLS FIRST'
)
""")

# zorder
spark.sql("""
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample', strategy => 'sort', sort_order => 'zorder(c1,c2)'
)
""")

# only rewrite partitions with >=2 small files, and drop dangling deletes
spark.sql("""
CALL catalog_name.system.rewrite_data_files(
  table => 'db.sample',
  options => map('min-input-files', '2', 'remove-dangling-deletes', 'true')
)
""")

# only rewrite files that may match a predicate
spark.sql("""
CALL catalog_name.system.rewrite_data_files(table => 'db.sample', where => 'id = 3 and name = "foo"')
""")
```

Output: `rewritten_data_files_count`, `added_data_files_count`,
`rewritten_bytes_count`, `failed_data_files_count` (under partial
progress), `removed_delete_files_count`.

## `rewrite_manifests`

Rewrites and re-clusters manifest files by partition spec fields, to
speed up scan planning. Invalidates cached Spark plans.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | |
| `use_caching` | no | boolean | false; enabling raises executor memory footprint |
| `spec_id` | no | int | defaults to current spec id |
| `sort_by` | no | array | partition transform names to cluster by; defaults to all spec fields |

```python
spark.sql("CALL catalog_name.system.rewrite_manifests('db.sample')")
spark.sql("CALL catalog_name.system.rewrite_manifests(table => 'db.sample', spec_id => 1)")
spark.sql("CALL catalog_name.system.rewrite_manifests(table => 'db.sample', sort_by => array('category'))")
```

Output: `rewritten_manifests_count`, `added_manifests_count`.

## `rewrite_position_delete_files`

Compacts small position-delete files into larger ones and drops "dangling"
deletes (deletes pointing at data files no longer live — a common
side-effect of running `rewrite_data_files` without
`remove-dangling-deletes`).

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | |
| `options` | no | map | see below |
| `where` | no | string | filter predicate |

Options: same shape as `rewrite_data_files` general options
(`max-concurrent-file-group-rewrites`, `partial-progress.*`,
`rewrite-job-order`, `min-file-size-bytes`, `max-file-size-bytes`,
`min-input-files`, `rewrite-all`, `max-file-group-size-bytes`,
`max-files-to-rewrite`), except `target-file-size-bytes` here defaults to
67108864 (64MB, from `write.delete.target-file-size-bytes`). Dangling
deletes are always removed during rewriting, regardless of options.

```python
spark.sql("CALL catalog_name.system.rewrite_position_delete_files('db.sample')")

spark.sql("""
CALL catalog_name.system.rewrite_position_delete_files(table => 'db.sample', options => map('rewrite-all', 'true'))
""")

spark.sql("""
CALL catalog_name.system.rewrite_position_delete_files(table => 'db.sample', options => map('min-input-files','2'))
""")
```

Output: `rewritten_delete_files_count`, `added_delete_files_count`,
`rewritten_bytes_count`, `added_bytes_count`.

# Table Migration

## `snapshot`

Creates a lightweight, isolated **test** copy of a table sharing the
source's existing data files (writes to the snapshot land in the
snapshot's own location, source is untouched). Clean up with
`DROP TABLE`. Because a snapshot table doesn't own its data files, it
cannot run `expire_snapshots` (would physically delete shared files);
metadata-only Iceberg deletes are fine. Any change to the *original*
table's data files (e.g. a Hive `DELETE`) corrupts the snapshot's view.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `source_table` | yes | string | |
| `table` | yes | string | name of the new Iceberg table |
| `location` | no | string | defaults to catalog's default location |
| `properties` | no | map | properties for the new table |
| `parallelism` | no | int | file-reading thread count, default 1 |
| `ignore_missing_files` | no | boolean | false; skip source data files that can't be found (1.12+) |

```python
spark.sql("CALL catalog_name.system.snapshot('db.sample', 'db.snap')")
spark.sql("CALL catalog_name.system.snapshot('db.sample', 'db.snap', '/tmp/temptable/')")
```

Output: `imported_files_count`.

## `migrate`

**Replaces** a Hive/Spark table with an Iceberg table in place, loading
the source's existing data files (schema/partitioning/properties/location
copied from the source). Fails on unsupported partition formats (only
Avro, Parquet, ORC supported) or bucketed tables. Original table retained
as backup (`table_BACKUP_<n>` by default) unless disabled.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | |
| `properties` | no | map | properties for the new Iceberg table |
| `drop_backup` | no | boolean | false; if true, no backup table is kept |
| `backup_table_name` | no | string | default `table_BACKUP_` |
| `parallelism` | no | int | default 1 |
| `ignore_missing_files` | no | boolean | false; skip source data files that can't be found (1.12+) |

```python
spark.sql("CALL catalog_name.system.migrate('spark_catalog.db.sample', map('foo', 'bar'))")
spark.sql("CALL catalog_name.system.migrate('db.sample')")
```

Output: `migrated_files_count`. Use `snapshot` instead to test without
altering the original table.

## `add_files`

Registers existing files from a Hive/file-based table (or path) directly
into an *existing* Iceberg table's metadata, without moving them or
validating schema match. Does not create a new table (unlike
`migrate`/`snapshot`). Added files become fully Iceberg-owned — a later
`expire_snapshots` can physically delete them.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | target Iceberg table |
| `source_table` | yes | string | source table, or `` `file_format`.`path` `` |
| `partition_filter` | no | map | restrict to matching partitions |
| `check_duplicate_files` | no | boolean | true; prevents re-adding files already present |
| `parallelism` | no | int | default 1 |

```python
spark.sql("""
CALL spark_catalog.system.add_files(
  table => 'db.tbl',
  source_table => 'db.src_tbl',
  partition_filter => map('part_col_1', 'A')
)
""")

spark.sql("""
CALL spark_catalog.system.add_files(
  table => 'db.tbl',
  source_table => '`parquet`.`path/to/table`'
)
""")
```

Output: `added_files_count`, `changed_partition_count` (`NULL` if
`compatibility.snapshot-id-inheritance.enabled=true` or table format
version > 1).

> Warning: schema is not validated on add — mismatched schemas cause
> downstream issues. Tiered-storage files (e.g. S3 Intelligent-Tiering)
> get their Parquet footer fetched once during this call, which can pull
> archived objects to a hotter storage tier.

## `register_table`

Creates a catalog entry pointing at an existing `metadata.json` that has
no catalog identifier yet (e.g. moving a table between catalogs).

| Argument | Required | Type |
|---|---|---|
| `table` | yes | string |
| `metadata_file` | yes | string |

```python
spark.sql("""
CALL spark_catalog.system.register_table(
  table => 'db.tbl',
  metadata_file => 'path/to/metadata/file.json'
)
""")
```

Output: `current_snapshot_id`, `total_records_count`,
`total_data_files_count`.

> Warning: never register the same `metadata.json` into more than one
> catalog at once — leads to missed updates and table corruption.

# Metadata Information

## `ancestors_of`

Reports live snapshot IDs on the ancestor chain of a given (or current)
snapshot.

| Argument | Required | Type |
|---|---|---|
| `table` | yes | string |
| `snapshot_id` | no | long |

```python
spark.sql("CALL spark_catalog.system.ancestors_of('db.tbl')")            # current snapshot's ancestors
spark.sql("CALL spark_catalog.system.ancestors_of('db.tbl', 1)")          # ancestors of a specific snapshot
spark.sql("CALL spark_catalog.system.ancestors_of(snapshot_id => 1, table => 'db.tbl')")
```

Output: `snapshot_id`, `timestamp` (one row per ancestor).

# Change Data Capture

## `create_changelog_view`

Creates a view exposing row-level changes between two snapshots/timestamps
with CDC metadata columns.

| Argument | Required | Type | Notes |
|---|---|---|---|
| `table` | yes | string | source table |
| `changelog_view` | no | string | output view name |
| `options` | no | map | Spark read options — see below |
| `net_changes` | no | boolean | false; collapse intermediate changes to net effect only; must be false if `compute_updates` is true |
| `compute_updates` | no | boolean | defaults true if `identifier_columns` given, else false |
| `identifier_columns` | no | array | columns identifying "same row" for update detection; defaults to the table's identifier fields |

Common `options` keys: `start-snapshot-id` (exclusive), `end-snapshot-id`
(inclusive, default current), `start-timestamp` (exclusive),
`end-timestamp` (inclusive, default current).

```python
spark.sql("""
CALL spark_catalog.system.create_changelog_view(
  table => 'db.tbl',
  options => map('start-snapshot-id','1','end-snapshot-id', '2')
)
""")

spark.sql("""
CALL spark_catalog.system.create_changelog_view(
  table => 'db.tbl',
  options => map('start-timestamp','1678335750489','end-timestamp', '1678992105265'),
  changelog_view => 'my_changelog_view'
)
""")

spark.sql("""
CALL spark_catalog.system.create_changelog_view(
  table => 'db.tbl',
  options => map('start-snapshot-id','1','end-snapshot-id', '2'),
  identifier_columns => array('id', 'name')
)
""")

spark.sql("SELECT * FROM tbl_changes")
spark.sql("SELECT * FROM tbl_changes where _change_type = 'INSERT' AND id = 3 ORDER BY _change_ordinal")
```

Output: `changelog_view` (the created view's name).

CDC metadata columns on the view: `_change_type` (`INSERT`, `DELETE`,
`UPDATE_BEFORE`, `UPDATE_AFTER`), `_change_ordinal` (change order),
`_commit_snapshot_id`.

### Net changes

```python
spark.sql("""
CALL spark_catalog.system.create_changelog_view(
  table => 'db.tbl',
  options => map('end-snapshot-id', '87647489814522183702'),
  net_changes => true
)
""")
```

Collapses multi-snapshot intermediate changes (e.g. insert-then-delete of
the same row across snapshots disappears entirely) into just the net
effect.

### Carry-over rows

Copy-on-write `MERGE`/`UPDATE`/`DELETE` can rewrite a file to drop one row
while re-writing an untouched row into a new file — the changelog reports
that untouched row as a spurious `DELETE`+`INSERT` pair ("carry-over").
`create_changelog_view` removes these by default; to see them raw, query
`SparkChangelogTable` directly:

```python
spark.sql("SELECT * FROM spark_catalog.db.tbl.changes")
```

### Pre/post update images

When `compute_updates` is enabled and identifier columns are known, a
matching delete+insert pair (same identifier values) is reported as a
single logical update: `UPDATE_BEFORE` / `UPDATE_AFTER` instead of raw
`DELETE`/`INSERT`.

# Table Statistics

## `compute_table_stats`

Computes Number-of-Distinct-Values (NDV) statistics (Puffin/Theta sketch)
for a table, by default all columns at the current snapshot.

| Argument | Required | Type |
|---|---|---|
| `table` | yes | string |
| `snapshot_id` | no | string |
| `columns` | no | array |

```python
spark.sql("CALL catalog_name.system.compute_table_stats('my_table')")
spark.sql("CALL catalog_name.system.compute_table_stats(table => 'my_table', snapshot_id => 'snap1')")
spark.sql("""
CALL catalog_name.system.compute_table_stats(table => 'my_table', snapshot_id => 'snap1', columns => array('col1', 'col2'))
""")
```

Output: `statistics_file` (path to the stats file written).

# Partition Statistics

## `compute_partition_stats`

Incrementally computes partition statistics from the last
`PartitionStatisticsFile` up to a given (or current) snapshot, writing a
combined `PartitionStatisticsFile` and registering it in table metadata.
Does a full compute if no prior stats file exists.

| Argument | Required | Type |
|---|---|---|
| `table` | yes | string |
| `snapshot_id` | no | string (defaults to current) |

```python
spark.sql("CALL catalog_name.system.compute_partition_stats('my_table')")
spark.sql("CALL catalog_name.system.compute_partition_stats(table => 'my_table', snapshot_id => 'snap1')")
```

Output: `partition_statistics_file`.

# Table Replication

## `rewrite_table_path`

Stages a rewritten copy of a table's metadata files with all absolute
source-prefix paths swapped for a target prefix — the first step of
copying an Iceberg table to a new location (actual file copy is a
separate step, e.g. via Distcp, followed by `register_table` at the
target).

| Argument | Required | Default | Type | Notes |
|---|---|---|---|---|
| `table` | yes | | string | |
| `source_prefix` | yes | | string | prefix to replace |
| `target_prefix` | yes | | string | replacement prefix |
| `start_version` | no | first metadata.json | string | start of incremental rewrite range |
| `end_version` | no | latest metadata.json | string | end of incremental rewrite range |
| `staging_location` | no | new dir under table metadata dir | string | output location for rewritten files |
| `create_file_list` | no | true | boolean | emit a copy-plan file list |

Two modes: **full rewrite** (default — rewrites all reachable metadata:
metadata.json, manifest lists, manifests, position delete files) or
**incremental rewrite** (only files added between `start_version` and
`end_version`, via those two args).

```python
spark.sql("""
CALL catalog_name.system.rewrite_table_path(
    table => 'db.my_table',
    source_prefix => 'hdfs://nn:8020/path/to/source_table',
    target_prefix => 's3a://bucket/prefix/db.db/my_table'
)
""")

spark.sql("""
CALL catalog_name.system.rewrite_table_path(
    table => 'db.my_table',
    source_prefix => 's3a://bucketOne/prefix/db.db/my_table',
    target_prefix => 's3a://bucketTwo/prefix/db.db/my_table',
    start_version => 'v2.metadata.json',
    end_version => 'v20.metadata.json',
    staging_location => 's3a://bucketStaging/my_table'
)
""")
```

Output: `latest_version`, `file_list_location` (CSV of source→target
path pairs), `rewritten_manifest_file_paths_count`,
`rewritten_delete_file_paths_count`.

> Tables with partition statistics files are not currently supported by
> `rewrite_table_path` (per the 1.12 procedure docs). Note that the 1.11.0
> release notes list "Add Support for PartitionStatistics Files in
> RewriteTablePath (#13956)" — test on your version before relying on either.

# Citations

[1] [Spark Procedures](https://iceberg.apache.org/docs/latest/spark-procedures)
