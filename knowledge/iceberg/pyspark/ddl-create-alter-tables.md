---
type: PySpark Guide
title: DDL — Create, Alter, and Drop Iceberg Tables in PySpark
description: CREATE TABLE, CTAS/RTAS, ALTER TABLE (columns, partition fields, sort order, identifier fields, branches/tags), DROP TABLE, and Iceberg views, all via spark.sql(...) in PySpark.
aliases: [iceberg create table pyspark, alter table add column iceberg, iceberg partition transform, spark ddl iceberg, drop table purge, create table as select iceberg, iceberg add partition field]
tags: [iceberg, pyspark, spark, ddl, sql, partitioning, schema-evolution]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/spark-ddl
---

# Retrieval Notes

Read this for anything schema/DDL shaped: creating tables, adding/dropping
columns, evolving partition specs, setting sort order, branches/tags, or
Iceberg views. Requires a configured catalog and (for the `ALTER TABLE`
extension commands, branching/tagging) `spark.sql.extensions` — see
`/pyspark/setup-and-configuration.md`. For hidden partitioning concepts and
transform semantics in depth, see
`/architecture/partitioning-and-hidden-partitioning.md`. For row-level
writes/upserts see `/pyspark/writing-data.md` and
`/pyspark/merge-into-and-row-level-operations.md`.

# Summary

- `CREATE TABLE ... USING iceberg` works in any Iceberg catalog; supports
  `PARTITIONED BY`, `LOCATION`, `COMMENT`, `TBLPROPERTIES`. `CREATE TABLE ...
  LIKE ...` is **not** supported.
- `PARTITIONED BY` accepts hidden-partition transforms: `bucket(N, col)`,
  `truncate(L, col)`, `year/month/day(or date)/hour(or date_hour)(ts)`,
  or plain column names for identity partitioning.
- CTAS (`CREATE TABLE ... AS SELECT`) and RTAS (`REPLACE TABLE ... AS
  SELECT` / `CREATE OR REPLACE TABLE ... AS SELECT`) are atomic only under
  `SparkCatalog`, not `SparkSessionCatalog`. The new table does **not**
  inherit the source table's partition spec/properties — declare them
  explicitly.
- `DROP TABLE` only removes the table from the catalog (since Iceberg
  0.14); use `DROP TABLE ... PURGE` to also delete the underlying data.
- `ALTER TABLE` supports rename, `SET`/`UNSET TBLPROPERTIES`, add/rename/
  drop columns (including nested struct/array/map fields), type widening
  (`int`→`bigint`, `float`→`double`, `decimal` precision increase), column
  reordering (`FIRST`/`AFTER`), and `DROP NOT NULL`. **You cannot** go from
  nullable to `NOT NULL`.
- SQL-extension-only `ALTER TABLE` commands (need
  `IcebergSparkSessionExtensions`): `ADD/DROP/REPLACE PARTITION FIELD`,
  `WRITE ORDERED BY` / `WRITE LOCALLY ORDERED BY` / `WRITE DISTRIBUTED BY
  PARTITION`, `SET/DROP IDENTIFIER FIELDS`, and branch/tag DDL (`CREATE
  BRANCH`, `CREATE TAG`, `REPLACE BRANCH/TAG`, `DROP BRANCH/TAG`).
- **Hive Metastore catalog limitation:** HMS validates schema changes
  positionally (`hive.metastore.disallow.incompatible.col.type.changes`,
  default `true`). Any op that shifts column position (`ADD COLUMN ...
  FIRST/AFTER`, `ALTER COLUMN ... FIRST/AFTER`, `DROP COLUMN` on a non-last
  column) fails on a Hive catalog unless that property is disabled — and
  disabling it means plain Hive (not Iceberg-aware engines) may misread the
  table afterward.

# CREATE TABLE

```python
spark.sql("""
CREATE TABLE prod.db.sample (
    id bigint NOT NULL COMMENT 'unique id',
    data string)
USING iceberg
""")
```

Iceberg converts Spark column types to Iceberg types automatically — see
the Spark type-compatibility tables on the Iceberg "Spark Getting Started"
page (cited below).

## PARTITIONED BY

```python
spark.sql("""
CREATE TABLE prod.db.sample (
    id bigint,
    data string,
    category string)
USING iceberg
PARTITIONED BY (category)
""")
```

Hidden-partition transforms:

```python
spark.sql("""
CREATE TABLE prod.db.sample (
    id bigint,
    data string,
    category string,
    ts timestamp)
USING iceberg
PARTITIONED BY (bucket(16, id), days(ts), category)
""")
```

| Transform | Meaning |
|---|---|
| `year(ts)` | partition by year |
| `month(ts)` | partition by month |
| `day(ts)` / `date(ts)` | dateint-equivalent partitioning |
| `hour(ts)` / `date_hour(ts)` | dateint+hour-equivalent partitioning |
| `bucket(N, col)` | hashed value mod N buckets |
| `truncate(L, col)` | strings truncated to length L; ints/longs binned (`truncate(10, i)` → 0, 10, 20, ...) |

Old forms `years(ts)`, `months(ts)`, `days(ts)`, `hours(ts)` remain
supported for compatibility. The same transforms exist as Spark SQL
functions under `system.*` for filters — see
`/pyspark/reading-data-and-queries.md`.

Full clause support for `CREATE TABLE` / CTAS / RTAS:

| Clause | Purpose |
|---|---|
| `PARTITIONED BY (...)` | Partitioning, including transforms |
| `LOCATION '<uri>'` | Table location |
| `COMMENT '<text>'` | Table description |
| `TBLPROPERTIES ('key'='value', ...)` | Table configuration |
| `USING <format>` | Default format (SparkCatalog only) |

# CREATE TABLE ... AS SELECT (CTAS)

```python
spark.sql("CREATE TABLE prod.db.sample USING iceberg AS SELECT * FROM prod.db.source")
```

Atomic under `SparkCatalog`, not atomic under `SparkSessionCatalog`. Declare
partitioning/properties explicitly — CTAS does not inherit them from the
source:

```python
spark.sql("""
CREATE TABLE prod.db.sample
USING iceberg
PARTITIONED BY (part)
TBLPROPERTIES ('key'='value')
AS SELECT ...
""")
```

# REPLACE TABLE ... AS SELECT (RTAS)

Atomic under `SparkCatalog`; keeps table history while replacing data with
a new snapshot. Schema/partition spec are replaced if changed; new table
properties are merged with existing ones (changed ones updated, others
preserved).

```python
spark.sql("REPLACE TABLE prod.db.sample USING iceberg AS SELECT ...")

spark.sql("""
REPLACE TABLE prod.db.sample
USING iceberg
PARTITIONED BY (part)
TBLPROPERTIES ('key'='value')
AS SELECT ...
""")

spark.sql("CREATE OR REPLACE TABLE prod.db.sample USING iceberg AS SELECT ...")
```

To avoid changing schema/partitioning, use `INSERT OVERWRITE` instead (see
`/pyspark/writing-data.md`).

# DROP TABLE

```python
# Removes the table from the catalog only (since Iceberg 0.14) — data remains on disk
spark.sql("DROP TABLE prod.db.sample")

# Removes the table from the catalog AND deletes its data
spark.sql("DROP TABLE prod.db.sample PURGE")
```

# ALTER TABLE

## Rename

```python
spark.sql("ALTER TABLE prod.db.sample RENAME TO prod.db.new_name")
```

## Table properties

```python
spark.sql("""
ALTER TABLE prod.db.sample SET TBLPROPERTIES (
    'read.split.target-size'='268435456'
)
""")

spark.sql("ALTER TABLE prod.db.sample UNSET TBLPROPERTIES ('read.split.target-size')")

# Table comment is set as a special property
spark.sql("ALTER TABLE prod.db.sample SET TBLPROPERTIES ('comment' = 'A table comment.')")
```

## Add columns

```python
spark.sql("""
ALTER TABLE prod.db.sample
ADD COLUMNS (
    new_column string comment 'new_column docs'
)
""")
```

Nested columns use full dotted names:

```python
# create a struct column, then add a field to it
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN point struct<x: double, y: double>")
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN point.z double")

# array of struct: use 'element' to reach the array's element column
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN points array<struct<x: double, y: double>>")
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN points.element.z double")

# map of struct key / struct value: use 'value' to reach the map's value column
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN points map<struct<x: int>, struct<a: int>>")
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN points.value.b int")
```

Map `key` columns cannot have fields added — only map values.

Position a new column with `FIRST` / `AFTER`:

```python
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN new_column bigint AFTER other_column")
spark.sql("ALTER TABLE prod.db.sample ADD COLUMN nested.new_column bigint FIRST")
```

## Rename column

```python
spark.sql("ALTER TABLE prod.db.sample RENAME COLUMN data TO payload")
spark.sql("ALTER TABLE prod.db.sample RENAME COLUMN location.lat TO latitude")
```

Nested renames only rename the leaf field (`location.lat` → `location.latitude`).

## Alter column (widen type, comment, reorder, drop-not-null)

Safe type widenings only: `int`→`bigint`, `float`→`double`,
`decimal(P,S)`→`decimal(P2,S)` where P2 > P (scale is fixed).

```python
spark.sql("ALTER TABLE prod.db.sample ALTER COLUMN measurement TYPE double")

spark.sql("""
ALTER TABLE prod.db.sample ALTER COLUMN measurement TYPE double
COMMENT 'unit is bytes per second'
""")
spark.sql("ALTER TABLE prod.db.sample ALTER COLUMN measurement COMMENT 'unit is kilobytes per second'")

spark.sql("ALTER TABLE prod.db.sample ALTER COLUMN col FIRST")
spark.sql("ALTER TABLE prod.db.sample ALTER COLUMN nested.col AFTER other_col")

spark.sql("ALTER TABLE prod.db.sample ALTER COLUMN id DROP NOT NULL")
```

Notes: use `ADD COLUMN` / `DROP COLUMN` (not `ALTER COLUMN`) to add/remove
struct fields. You cannot go the other direction — `SET NOT NULL` is not
supported because Iceberg cannot verify existing rows have no nulls.

## Drop column

```python
spark.sql("ALTER TABLE prod.db.sample DROP COLUMN id")
spark.sql("ALTER TABLE prod.db.sample DROP COLUMN point.z")
```

# ALTER TABLE — SQL Extension Commands

Require `spark.sql.extensions =
org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions`.

## Partition evolution

```python
spark.sql("ALTER TABLE prod.db.sample ADD PARTITION FIELD catalog")  # identity transform
spark.sql("ALTER TABLE prod.db.sample ADD PARTITION FIELD bucket(16, id)")
spark.sql("ALTER TABLE prod.db.sample ADD PARTITION FIELD truncate(4, data)")
spark.sql("ALTER TABLE prod.db.sample ADD PARTITION FIELD year(ts)")
spark.sql("ALTER TABLE prod.db.sample ADD PARTITION FIELD bucket(16, id) AS shard")  # custom name

spark.sql("ALTER TABLE prod.db.sample DROP PARTITION FIELD catalog")
spark.sql("ALTER TABLE prod.db.sample DROP PARTITION FIELD bucket(16, id)")
spark.sql("ALTER TABLE prod.db.sample DROP PARTITION FIELD shard")

spark.sql("ALTER TABLE prod.db.sample REPLACE PARTITION FIELD ts_day WITH day(ts)")
spark.sql("ALTER TABLE prod.db.sample REPLACE PARTITION FIELD ts_day WITH day(ts) AS day_of_ts")
```

Adding/dropping a partition field is metadata-only: existing data keeps its
old layout, new data uses the new spec, and old files show `null` for the
new field in metadata tables. Keeping an old field (e.g. daily) when moving
to a finer one (e.g. hourly) preserves compatibility with existing
metadata-table queries.

> **Danger:** dynamic partition overwrite behavior changes when the
> partition spec changes — e.g. moving from day to hour partitioning means
> overwrites now target hour partitions, not day partitions. Dropping a
> partition field also changes the schema of metadata tables like `files`
> and can break metadata queries.

## Write order and distribution

```python
spark.sql("ALTER TABLE prod.db.sample WRITE ORDERED BY category, id")
spark.sql("ALTER TABLE prod.db.sample WRITE ORDERED BY category ASC, id DESC")
spark.sql("ALTER TABLE prod.db.sample WRITE ORDERED BY category ASC NULLS LAST, id DESC NULLS FIRST")

# order within each task only (not globally across tasks)
spark.sql("ALTER TABLE prod.db.sample WRITE LOCALLY ORDERED BY category, id")

# remove the sort order
spark.sql("ALTER TABLE prod.db.sample WRITE UNORDERED")

# one writer handles each partition (hash distribution by default)
spark.sql("ALTER TABLE prod.db.sample WRITE DISTRIBUTED BY PARTITION")

# combine: distribute by partition, locally order within each task
spark.sql("ALTER TABLE prod.db.sample WRITE DISTRIBUTED BY PARTITION LOCALLY ORDERED BY category, id")
```

Table write order affects how data is *written*, not query result order.
Engines like Spark's `MERGE INTO` use the configured table order.

## Identifier fields

```python
spark.sql("ALTER TABLE prod.db.sample SET IDENTIFIER FIELDS id")
spark.sql("ALTER TABLE prod.db.sample SET IDENTIFIER FIELDS id, data")  # multiple columns

spark.sql("ALTER TABLE prod.db.sample DROP IDENTIFIER FIELDS id")
spark.sql("ALTER TABLE prod.db.sample DROP IDENTIFIER FIELDS id, data")
```

Identifier fields must be `NOT NULL`. A later `SET IDENTIFIER FIELDS`
overwrites the previous setting. Dropping an identifier field leaves the
column itself in the schema. (These enable e.g. Flink SQL upsert against
the table.)

## Branches and tags

```python
spark.sql("ALTER TABLE prod.db.sample CREATE BRANCH `audit-branch`")
spark.sql("ALTER TABLE prod.db.sample CREATE BRANCH IF NOT EXISTS `audit-branch`")
spark.sql("ALTER TABLE prod.db.sample CREATE OR REPLACE BRANCH `audit-branch`")
spark.sql("ALTER TABLE prod.db.sample CREATE BRANCH `audit-branch` AS OF VERSION 1234")
spark.sql("""
ALTER TABLE prod.db.sample CREATE BRANCH `audit-branch`
AS OF VERSION 1234 RETAIN 30 DAYS
WITH SNAPSHOT RETENTION 3 SNAPSHOTS 2 DAYS
""")

spark.sql("ALTER TABLE prod.db.sample CREATE TAG `historical-tag`")
spark.sql("ALTER TABLE prod.db.sample CREATE TAG IF NOT EXISTS `historical-tag`")
spark.sql("ALTER TABLE prod.db.sample CREATE OR REPLACE TAG `historical-tag`")
spark.sql("ALTER TABLE prod.db.sample CREATE TAG `historical-tag` AS OF VERSION 1234")
spark.sql("""
ALTER TABLE prod.db.sample CREATE TAG `historical-tag`
AS OF VERSION 1234 RETAIN 365 DAYS
""")

spark.sql("""
ALTER TABLE prod.db.sample REPLACE BRANCH `audit-branch`
AS OF VERSION 4567 RETAIN 60 DAYS
""")
spark.sql("""
ALTER TABLE prod.db.sample REPLACE TAG `historical-tag`
AS OF VERSION 4567 RETAIN 60 DAYS
""")

spark.sql("ALTER TABLE prod.db.sample DROP BRANCH `audit-branch`")
spark.sql("ALTER TABLE prod.db.sample DROP TAG `historical-tag`")
```

See [/architecture/branching-and-tagging.md](/architecture/branching-and-tagging.md) for branch/tag semantics
and use cases such as Write-Audit-Publish.

# Iceberg Views in Spark (3.4+)

Iceberg views follow the [view spec](https://iceberg.apache.org/view-spec/)
and use standard Spark SQL view syntax.

```python
spark.sql("CREATE VIEW my_view AS SELECT * FROM prod.db.sample")
spark.sql("CREATE VIEW IF NOT EXISTS my_view AS SELECT * FROM prod.db.sample")

spark.sql("""
CREATE VIEW my_view (ID COMMENT 'Unique ID', ZIP COMMENT 'Zipcode')
    COMMENT 'View Comment'
    AS SELECT id, zip FROM prod.db.sample
""")

spark.sql("""
CREATE VIEW my_view
    TBLPROPERTIES ('key1' = 'val1', 'key2' = 'val2')
    AS SELECT * FROM prod.db.sample
""")
spark.sql("SHOW TBLPROPERTIES my_view")

# custom metadata location — stored under <location>/metadata
spark.sql("""
CREATE VIEW my_view
    TBLPROPERTIES ('location' = '/path/to/custom-location')
    AS SELECT * FROM prod.db.sample
""")

spark.sql("DROP VIEW my_view")
spark.sql("DROP VIEW IF EXISTS my_view")

spark.sql("""
CREATE OR REPLACE VIEW my_view (updated_id COMMENT 'updated ID')
    TBLPROPERTIES ('key1' = 'new_val1')
    AS SELECT id FROM prod.db.sample
""")

spark.sql("ALTER VIEW my_view SET TBLPROPERTIES ('key1' = 'val1', 'key2' = 'val2')")
spark.sql("ALTER VIEW my_view UNSET TBLPROPERTIES ('key1', 'key2')")

spark.sql("SHOW VIEWS")                 # in current namespace
spark.sql("SHOW VIEWS IN prod")         # in a catalog
spark.sql("SHOW VIEWS IN prod.db")      # in a namespace

spark.sql("SHOW CREATE TABLE my_view")
spark.sql("DESCRIBE EXTENDED my_view")
```

# Citations

[1] [Spark DDL](https://iceberg.apache.org/docs/latest/spark-ddl)
[2] [Spark Getting Started — Type compatibility](https://iceberg.apache.org/docs/latest/spark-getting-started/#type-compatibility)
