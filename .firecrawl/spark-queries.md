[Skip to content](https://iceberg.apache.org/docs/latest/spark-queries/#spark-queries)

# Spark Queries [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#spark-queries "Permanent link")

To use Iceberg in Spark, first configure [Spark catalogs](https://iceberg.apache.org/docs/latest/spark-configuration/). Iceberg uses Apache Spark's DataSourceV2 API for data source and catalog implementations.

## Querying with SQL [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#querying-with-sql "Permanent link")

In Spark, tables use identifiers that include a [catalog name](https://iceberg.apache.org/docs/latest/spark-configuration/#using-catalogs).

```
SELECT * FROM prod.db.table; -- catalog: prod, namespace: db, table: table
```

Metadata tables, like `history` and `snapshots`, can use the Iceberg table name as a namespace.

For example, to read from the `files` metadata table for `prod.db.table`:

```
SELECT * FROM prod.db.table.files;
```

| content | file\_path | file\_format | spec\_id | partition | record\_count | file\_size\_in\_bytes | column\_sizes | value\_counts | null\_value\_counts | nan\_value\_counts | lower\_bounds | upper\_bounds | key\_metadata | split\_offsets | equality\_ids | sort\_order\_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | s3:/.../table/data/00000-3-8d6d60e8-d427-4809-bcf0-f5d45a4aad96.parquet | PARQUET | 0 | {1999-01-01, 01} | 1 | 597 | \[1 -> 90, 2 -> 62\] | \[1 -> 1, 2 -> 1\] | \[1 -> 0, 2 -> 0\] | \[\] | \[1 -> , 2 -> c\] | \[1 -> , 2 -> c\] | null | \[4\] | null | null |
| 0 | s3:/.../table/data/00001-4-8d6d60e8-d427-4809-bcf0-f5d45a4aad96.parquet | PARQUET | 0 | {1999-01-01, 02} | 1 | 597 | \[1 -> 90, 2 -> 62\] | \[1 -> 1, 2 -> 1\] | \[1 -> 0, 2 -> 0\] | \[\] | \[1 -> , 2 -> b\] | \[1 -> , 2 -> b\] | null | \[4\] | null | null |
| 0 | s3:/.../table/data/00002-5-8d6d60e8-d427-4809-bcf0-f5d45a4aad96.parquet | PARQUET | 0 | {1999-01-01, 03} | 1 | 597 | \[1 -> 90, 2 -> 62\] | \[1 -> 1, 2 -> 1\] | \[1 -> 0, 2 -> 0\] | \[\] | \[1 -> , 2 -> a\] | \[1 -> , 2 -> a\] | null | \[4\] | null | null |

### Spark SQL functions [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#spark-sql-functions "Permanent link")

Iceberg adds SQL functions to each Iceberg catalog for inspecting transform results in queries and for
writing filters that match Iceberg partition transforms. These functions are available only through an
[Iceberg catalog](https://iceberg.apache.org/docs/latest/spark-configuration/#catalog-configuration); they are not registered in Spark's
built-in catalog.

Note

Spark before 4.2.0 does not support `V2Function` in the session catalog.
Queries such as `SELECT spark_catalog.system.bucket(16, id)` fail even when
`spark_catalog` is configured with `org.apache.iceberg.spark.SparkSessionCatalog`.
See [SPARK-54760](https://issues.apache.org/jira/browse/SPARK-54760) ( [apache/spark#53531](https://github.com/apache/spark/pull/53531)) for details.
To use Iceberg SQL functions, call them through a catalog configured with
`org.apache.iceberg.spark.SparkCatalog`.

Use the `system` namespace when calling these functions:

```
SELECT system.iceberg_version();

SELECT system.bucket(16, id), system.days(ts)
FROM prod.db.table;
```

When you want to be explicit about the catalog, qualify the function with the catalog name:

```
SELECT prod.system.bucket(16, id)
FROM prod.db.table;
```

Info

`PARTITIONED BY` clauses use singular transform expressions such as `year(ts)` and `month(ts)`.
The SQL functions use `system.years(ts)` and `system.months(ts)`.

| Function | Supported input types | Return type | Example |
| --- | --- | --- | --- |
| `system.iceberg_version()` | none | `string` | `SELECT system.iceberg_version();` |
| `system.bucket(numBuckets, col)` | `date`, `tinyint`, `smallint`, `int`, `bigint`, `timestamp`, `timestamp_ntz`, `decimal`, `string`, `binary` | `int` | `SELECT system.bucket(16, id) FROM prod.db.table;` |
| `system.years(col)` | `date`, `timestamp`, `timestamp_ntz` | `int` | `SELECT system.years(ts) FROM prod.db.table;` |
| `system.months(col)` | `date`, `timestamp`, `timestamp_ntz` | `int` | `SELECT system.months(ts) FROM prod.db.table;` |
| `system.days(col)` | `date`, `timestamp`, `timestamp_ntz` | `date` | `SELECT * FROM prod.db.table WHERE system.days(ts) = date('2025-03-01');` |
| `system.hours(col)` | `timestamp`, `timestamp_ntz` | `int` | `SELECT system.hours(ts) FROM prod.db.table;` |
| `system.truncate(width, col)` | `tinyint`, `smallint`, `int`, `bigint`, `decimal`, `string`, `binary` | same type as `col` | `SELECT system.truncate(4, data) FROM prod.db.table;` |

All transform functions return `NULL` for `NULL` inputs.

`system.years`, `system.months`, `system.days`, and `system.hours` return Iceberg transform values
rather than extracted calendar fields. For example, `system.years` returns years since 1970-01-01,
`system.months` returns months since 1970-01, and `system.hours` returns hours since
1970-01-01T00:00. `system.days` returns a `date` value representing the date part of the input
(for `date` inputs it returns the same value unchanged; for timestamps it discards the time component).

For numeric inputs, `system.truncate(width, col)` rounds down to the nearest multiple of `width`.
For `string` and `binary` inputs, it keeps the first `width` characters or bytes.

These functions are especially useful when you want to inspect how Iceberg transforms values or
when writing filters for queries and row-level operations that align with partition transforms.

### Time travel Queries with SQL [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#time-travel-queries-with-sql "Permanent link")

Spark supports time travel in SQL queries using `TIMESTAMP AS OF` or `VERSION AS OF` clauses.
The `VERSION AS OF` clause can contain a long snapshot ID or a string branch or tag name.

Info

Note: If the name of a branch or tag is the same as a snapshot ID, then the snapshot which is selected for time travel is the snapshot
with the given snapshot ID. For example, consider the case where there is a tag named '1' and it references snapshot with ID 2.
If the version travel clause is `VERSION AS OF '1'`, time travel will be done to the snapshot with ID 1.
If this is not desired, rename the tag or branch with a well-defined prefix such as 'snapshot-1'.

```
-- time travel to October 26, 1986 at 01:21:00
SELECT * FROM prod.db.table TIMESTAMP AS OF '1986-10-26 01:21:00';

-- time travel to snapshot with id 10963874102873L
SELECT * FROM prod.db.table VERSION AS OF 10963874102873;

-- time travel to the head snapshot of audit-branch
SELECT * FROM prod.db.table VERSION AS OF 'audit-branch';

-- time travel to the snapshot referenced by the tag historical-snapshot
SELECT * FROM prod.db.table VERSION AS OF 'historical-snapshot';
```

In addition, `FOR SYSTEM_TIME AS OF` and `FOR SYSTEM_VERSION AS OF` clauses are also supported:

```
SELECT * FROM prod.db.table FOR SYSTEM_TIME AS OF '1986-10-26 01:21:00';
SELECT * FROM prod.db.table FOR SYSTEM_VERSION AS OF 10963874102873;
SELECT * FROM prod.db.table FOR SYSTEM_VERSION AS OF 'audit-branch';
SELECT * FROM prod.db.table FOR SYSTEM_VERSION AS OF 'historical-snapshot';
```

Timestamps may also be supplied as a Unix timestamp, in seconds:

```
-- timestamp in seconds
SELECT * FROM prod.db.table TIMESTAMP AS OF 499162860;
SELECT * FROM prod.db.table FOR SYSTEM_TIME AS OF 499162860;
```

The branch or tag may also be specified using a similar syntax to metadata tables, with `branch_<branchname>` or `tag_<tagname>`:

```
SELECT * FROM prod.db.table.`branch_audit-branch`;
SELECT * FROM prod.db.table.`tag_historical-snapshot`;
```

(Identifiers with "-" are not valid, and so must be escaped using back quotes.)

Note that the identifier with branch or tag may not be used in combination with `VERSION AS OF`.

#### Schema selection in time travel queries [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#schema-selection-in-time-travel-queries "Permanent link")

The different time travel queries mentioned in the previous section can use either the snapshot's schema or the table's schema:

```
-- time travel to October 26, 1986 at 01:21:00 -> uses the snapshot's schema
SELECT * FROM prod.db.table TIMESTAMP AS OF '1986-10-26 01:21:00';

-- time travel to snapshot with id 10963874102873L -> uses the snapshot's schema
SELECT * FROM prod.db.table VERSION AS OF 10963874102873;

-- time travel to the head of audit-branch -> uses the table's schema
SELECT * FROM prod.db.table VERSION AS OF 'audit-branch';
SELECT * FROM prod.db.table.`branch_audit-branch`;

-- time travel to the snapshot referenced by the tag historical-snapshot -> uses the snapshot's schema
SELECT * FROM prod.db.table VERSION AS OF 'historical-snapshot';
SELECT * FROM prod.db.table.`tag_historical-snapshot`;
```

For example, consider a table that evolves its schema over time, and see how each type of time travel query selects its schema:

```
-- snapshot S1: initial schema (id, status)
CREATE TABLE prod.db.orders (
  id BIGINT,
  status STRING
) USING iceberg;

INSERT INTO prod.db.orders VALUES (1, 'NEW'), (2, 'PAID');

-- record snapshot S1's snapshot_id and committed_at timestamp
-- e.g. snapshot_id = 101, committed_at = '2025-01-01 10:00:00'

-- snapshot S2: add a new column "total" and write new data
ALTER TABLE prod.db.orders ADD COLUMN total DOUBLE;

INSERT INTO prod.db.orders VALUES (3, 'PAID', 100.0);

-- now S2 is the current snapshot with schema (id, status, total)
```

Time travel queries that select a specific snapshot or timestamp use the
snapshot's schema:

```
-- uses the snapshot schema of S1: columns (id, status)
SELECT * FROM prod.db.orders VERSION AS OF 101;

SELECT * FROM prod.db.orders TIMESTAMP AS OF '2025-01-01 10:00:00';
```

In both queries above, the result only has `id` and `status`. The `total`
column does not exist in the S1 schema and is not visible, even though the
current table schema includes `total`.

Now create a branch and a tag that both reference S1:

```
-- branch "audit_branch" points to snapshot S1
ALTER TABLE prod.db.orders CREATE BRANCH audit_branch AS OF VERSION 101;

-- tag "first_load" also points to snapshot S1
ALTER TABLE prod.db.orders CREATE TAG first_load AS OF VERSION 101;
```

When you query a branch, Spark uses the table's current schema:

```
-- uses the table schema: columns (id, status, total)
SELECT * FROM prod.db.orders VERSION AS OF 'audit_branch';

-- equivalent identifier form
SELECT * FROM prod.db.orders.`branch_audit_branch`;
```

In these queries, the result has columns `(id, status, total)`. For the rows
from S1, `total` is returned as `NULL` because that column did not exist when
those rows were written.

When you query a tag, Spark uses the snapshot's schema referenced by the tag:

```
-- uses the snapshot schema of S1: columns (id, status)
SELECT * FROM prod.db.orders VERSION AS OF 'first_load';

-- equivalent identifier form
SELECT * FROM prod.db.orders.`tag_first_load`;
```

These queries only return `id` and `status`, because tags are bound to a
specific snapshot and use that snapshot's schema, even if the table's current
schema has evolved.

## Querying with DataFrames [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#querying-with-dataframes "Permanent link")

To load a table as a DataFrame, use `table`:

```
val df = spark.table("prod.db.table")
```

### Catalogs with DataFrameReader [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#catalogs-with-dataframereader "Permanent link")

Paths and table names can be loaded with Spark's `DataFrameReader` interface. How tables are loaded depends on how
the identifier is specified. When using `spark.read.format("iceberg").load(table)` or `spark.table(table)` the `table`
variable can take a number of forms as listed below:

- `file:///path/to/table`: loads a HadoopTable at given path
- `tablename`: loads `currentCatalog.currentNamespace.tablename`
- `catalog.tablename`: loads `tablename` from the specified catalog.
- `namespace.tablename`: loads `namespace.tablename` from current catalog
- `catalog.namespace.tablename`: loads `namespace.tablename` from the specified catalog.
- `namespace1.namespace2.tablename`: loads `namespace1.namespace2.tablename` from current catalog

The above list is in order of priority. For example: a matching catalog will take priority over any namespace resolution.

### Time travel Queries with DataFrame [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#time-travel-queries-with-dataframe "Permanent link")

To select a specific table snapshot or the snapshot at some time in the DataFrame API, Iceberg supports four Spark read options:

- `snapshot-id` selects a specific table snapshot
- `as-of-timestamp` selects the current snapshot at a timestamp, in milliseconds
- `branch` selects the head snapshot of the specified branch. Note that currently branch cannot be combined with as-of-timestamp.
- `tag` selects the snapshot associated with the specified tag. Tags cannot be combined with `as-of-timestamp`.

```
// time travel to October 26, 1986 at 01:21:00
spark.read
    .option("as-of-timestamp", "499162860000")
    .format("iceberg")
    .load("path/to/table")
```

```
// time travel to snapshot with ID 10963874102873L
spark.read
    .option("snapshot-id", 10963874102873L)
    .format("iceberg")
    .load("path/to/table")
```

```
// time travel to tag historical-snapshot
spark.read
    .option(SparkReadOptions.TAG, "historical-snapshot")
    .format("iceberg")
    .load("path/to/table")
```

```
// time travel to the head snapshot of audit-branch
spark.read
    .option(SparkReadOptions.BRANCH, "audit-branch")
    .format("iceberg")
    .load("path/to/table")
```

### Incremental read [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#incremental-read "Permanent link")

To read appended data incrementally, use:

- `start-snapshot-id` Start snapshot ID used in incremental scans (exclusive).
- `end-snapshot-id` End snapshot ID used in incremental scans (inclusive). This is optional. Omitting it will default to the current snapshot.

```
// get the data added after start-snapshot-id (10963874102873L) until end-snapshot-id (63874143573109L)
spark.read
  .format("iceberg")
  .option("start-snapshot-id", "10963874102873")
  .option("end-snapshot-id", "63874143573109")
  .load("path/to/table")
```

Info

Currently gets only the data from `append` operation. Cannot support `replace`, `overwrite`, `delete` operations.
Incremental read works with both V1 and V2 format-version.
Incremental read is not supported by Spark's SQL syntax.

## Inspecting tables [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#inspecting-tables "Permanent link")

To inspect a table's history, snapshots, and other metadata, Iceberg supports metadata tables.

Metadata tables are identified by adding the metadata table name after the original table name. For example, history for `db.table` is read using `db.table.history`.

### History [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#history "Permanent link")

To show table history:

```
SELECT * FROM prod.db.table.history;
```

| made\_current\_at | snapshot\_id | parent\_id | is\_current\_ancestor |
| --- | --- | --- | --- |
| 2019-02-08 03:29:51.215 | 5781947118336215154 | NULL | true |
| 2019-02-08 03:47:55.948 | 5179299526185056830 | 5781947118336215154 | true |
| 2019-02-09 16:24:30.13 | 296410040247533544 | 5179299526185056830 | false |
| 2019-02-09 16:32:47.336 | 2999875608062437330 | 5179299526185056830 | true |
| 2019-02-09 19:42:03.919 | 8924558786060583479 | 2999875608062437330 | true |
| 2019-02-09 19:49:16.343 | 6536733823181975045 | 8924558786060583479 | true |

Info

**This shows a commit that was rolled back.** The example has two snapshots with the same parent, and one is _not_ an ancestor of the current table state.

### Metadata Log Entries [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#metadata-log-entries "Permanent link")

To show table metadata log entries:

```
SELECT * from prod.db.table.metadata_log_entries;
```

| timestamp | file | latest\_snapshot\_id | latest\_schema\_id | latest\_sequence\_number |
| --- | --- | --- | --- | --- |
| 2022-07-28 10:43:52.93 | s3://.../table/metadata/00000-9441e604-b3c2-498a-a45a-6320e8ab9006.metadata.json | null | null | null |
| 2022-07-28 10:43:57.487 | s3://.../table/metadata/00001-f30823df-b745-4a0a-b293-7532e0c99986.metadata.json | 170260833677645300 | 0 | 1 |
| 2022-07-28 10:43:58.25 | s3://.../table/metadata/00002-2cc2837a-02dc-4687-acc1-b4d86ea486f4.metadata.json | 958906493976709774 | 0 | 2 |

### Snapshots [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#snapshots "Permanent link")

To show the valid snapshots for a table:

```
SELECT * FROM prod.db.table.snapshots;
```

| committed\_at | snapshot\_id | parent\_id | operation | manifest\_list | summary |
| --- | --- | --- | --- | --- | --- |
| 2019-02-08 03:29:51.215 | 57897183625154 | null | append | s3://.../table/metadata/snap-57897183625154-1.avro | { added-records -> 2478404, total-records -> 2478404, added-data-files -> 438, total-data-files -> 438, spark.app.id -> application\_1520379288616\_155055 } |

You can also join snapshots to table history. For example, this query will show table history, with the application ID that wrote each snapshot:

```
select
    h.made_current_at,
    s.operation,
    h.snapshot_id,
    h.is_current_ancestor,
    s.summary['spark.app.id']
from prod.db.table.history h
join prod.db.table.snapshots s
  on h.snapshot_id = s.snapshot_id
order by made_current_at;
```

| made\_current\_at | operation | snapshot\_id | is\_current\_ancestor | summary\[spark.app.id\] |
| --- | --- | --- | --- | --- |
| 2019-02-08 03:29:51.215 | append | 57897183625154 | true | application\_1520379288616\_155055 |
| 2019-02-09 16:24:30.13 | delete | 29641004024753 | false | application\_1520379288616\_151109 |
| 2019-02-09 16:32:47.336 | append | 57897183625154 | true | application\_1520379288616\_155055 |
| 2019-02-08 03:47:55.948 | overwrite | 51792995261850 | true | application\_1520379288616\_152431 |

### Entries [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#entries "Permanent link")

To show all the table's current manifest entries for both data and delete files.

```
SELECT * FROM prod.db.table.entries;
```

| status | snapshot\_id | sequence\_number | file\_sequence\_number | data\_file | readable\_metrics |
| --- | --- | --- | --- | --- | --- |
| 2 | 57897183625154 | 0 | 0 | {"content":0,"file\_path":"s3:/.../table/data/00047-25-833044d0-127b-415c-b874-038a4f978c29-00612.parquet","file\_format":"PARQUET","spec\_id":0,"record\_count":15,"file\_size\_in\_bytes":473,"column\_sizes":{1:103},"value\_counts":{1:15},"null\_value\_counts":{1:0},"nan\_value\_counts":{},"lower\_bounds":{1:},"upper\_bounds":{1:},"key\_metadata":null,"split\_offsets":\[4\],"equality\_ids":null,"sort\_order\_id":0} | {"c1":{"column\_size":103,"value\_count":15,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":3}} |

Note:

1. The columns in the `entries` table correspond to the [manifest entry fields](https://iceberg.apache.org/spec/#manifest-entry-fields):
   - `status`: Used to track additions and deletions
   - `snapshot_id`: The ID of the snapshot in which the file was added or removed
   - `sequence_number`: Used for ordering changes across snapshots
   - `file_sequence_number`: Indicates when the file was added
   - `data_file`: A struct containing metadata about the data file, see the [data file fields](https://iceberg.apache.org/spec/#data-file-fields)
2. The `readable_metrics` column provides a human-readable map of extended column-level metrics derived from the `data_file` column, making it easier to inspect and debug file-level statistics.

### Files [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#files "Permanent link")

To show a table's current files:

```
SELECT * FROM prod.db.table.files;
```

| content | file\_path | file\_format | spec\_id | record\_count | file\_size\_in\_bytes | column\_sizes | value\_counts | null\_value\_counts | nan\_value\_counts | lower\_bounds | upper\_bounds | key\_metadata | split\_offsets | equality\_ids | sort\_order\_id | readable\_metrics |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | s3:/.../table/data/00042-3-a9aa8b24-20bc-4d56-93b0-6b7675782bb5-00001.parquet | PARQUET | 0 | 1 | 652 | {1:52,2:48} | {1:1,2:1} | {1:0,2:0} | {} | {1:,2:d} | {1:,2:d} | NULL | \[4\] | NULL | 0 | {"data":{"column\_size":48,"value\_count":1,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":"d","upper\_bound":"d"},"id":{"column\_size":52,"value\_count":1,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":1}} |
| 0 | s3:/.../table/data/00000-0-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet | PARQUET | 0 | 1 | 643 | {1:46,2:48} | {1:1,2:1} | {1:0,2:0} | {} | {1:,2:a} | {1:,2:a} | NULL | \[4\] | NULL | 0 | {"data":{"column\_size":48,"value\_count":1,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":"a","upper\_bound":"a"},"id":{"column\_size":46,"value\_count":1,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":1}} |
| 0 | s3:/.../table/data/00001-1-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet | PARQUET | 0 | 2 | 644 | {1:49,2:51} | {1:2,2:2} | {1:0,2:0} | {} | {1:,2:b} | {1:,2:c} | NULL | \[4\] | NULL | 0 | {"data":{"column\_size":51,"value\_count":2,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":"b","upper\_bound":"c"},"id":{"column\_size":49,"value\_count":2,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":2,"upper\_bound":3}} |
| 1 | s3:/.../table/data/00081-4-a9aa8b24-20bc-4d56-93b0-6b7675782bb5-00001-deletes.parquet | PARQUET | 0 | 1 | 1560 | {2147483545:46,2147483546:152} | {2147483545:1,2147483546:1} | {2147483545:0,2147483546:0} | {} | {2147483545:,2147483546:s3:/.../table/data/00000-0-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet} | {2147483545:,2147483546:s3:/.../table/data/00000-0-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet} | NULL | \[4\] | NULL | NULL | {"data":{"column\_size":null,"value\_count":null,"null\_value\_count":null,"nan\_value\_count":null,"lower\_bound":null,"upper\_bound":null},"id":{"column\_size":null,"value\_count":null,"null\_value\_count":null,"nan\_value\_count":null,"lower\_bound":null,"upper\_bound":null}} |
| 2 | s3:/.../table/data/00047-25-833044d0-127b-415c-b874-038a4f978c29-00612.parquet | PARQUET | 0 | 126506 | 28613985 | {100:135377,101:11314} | {100:126506,101:126506} | {100:105434,101:11} | {} | {100:0,101:17} | {100:404455227527,101:23} | NULL | NULL | \[1\] | 0 | {"id":{"column\_size":135377,"value\_count":126506,"null\_value\_count":105434,"nan\_value\_count":null,"lower\_bound":0,"upper\_bound":404455227527},"data":{"column\_size":11314,"value\_count":126506,"null\_value\_count": 11,"nan\_value\_count":null,"lower\_bound":17,"upper\_bound":23}} |

Info

Content refers to type of content stored by the data file:

- 0 - Data
- 1 - Position Deletes
- 2 - Equality Deletes

To show only data files or delete files, query `prod.db.table.data_files` and `prod.db.table.delete_files` respectively.
To show all files, data files and delete files across all tracked snapshots, query `prod.db.table.all_files`, `prod.db.table.all_data_files` and `prod.db.table.all_delete_files` respectively.

### Manifests [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#manifests "Permanent link")

To show a table's current file manifests:

```
SELECT * FROM prod.db.table.manifests;
```

| content | path | length | partition\_spec\_id | added\_snapshot\_id | added\_data\_files\_count | existing\_data\_files\_count | deleted\_data\_files\_count | added\_delete\_files\_count | existing\_delete\_files\_count | deleted\_delete\_files\_count | partition\_summaries |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | s3://.../table/metadata/45b5290b-ee61-4788-b324-b1e2735c0e10-m0.avro | 4479 | 0 | 6668963634911763636 | 8 | 0 | 0 | 0 | 0 | 0 | \[\[false,null,2019-05-13,2019-05-15\]\] |

Note:

1. Fields within `partition_summaries` column of the manifests table correspond to `field_summary` structs within [manifest list](https://iceberg.apache.org/spec/#manifest-lists), with the following order:
   - `contains_null`
   - `contains_nan`
   - `lower_bound`
   - `upper_bound`
2. `contains_nan` could return null, which indicates that this information is not available from the file's metadata.
    This usually occurs when reading from V1 table, where `contains_nan` is not populated.

### Partitions [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#partitions "Permanent link")

To show a table's current partitions:

```
SELECT * FROM prod.db.table.partitions;
```

| partition | spec\_id | record\_count | file\_count | total\_data\_file\_size\_in\_bytes | position\_delete\_record\_count | position\_delete\_file\_count | equality\_delete\_record\_count | equality\_delete\_file\_count | last\_updated\_at(μs) | last\_updated\_snapshot\_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| {20211001, 11} | 0 | 1 | 1 | 100 | 2 | 1 | 0 | 0 | 1633086034192000 | 9205185327307503337 |
| {20211002, 11} | 0 | 4 | 3 | 500 | 1 | 1 | 0 | 0 | 1633172537358000 | 867027598972211003 |
| {20211001, 10} | 0 | 7 | 4 | 700 | 0 | 0 | 0 | 0 | 1633082598716000 | 3280122546965981531 |
| {20211002, 10} | 0 | 3 | 2 | 400 | 0 | 0 | 1 | 1 | 1633169159489000 | 6941468797545315876 |

Note:

1. For unpartitioned tables, the partitions table will not contain the partition and spec\_id fields.

2. The partitions metadata table shows partitions with data files or delete files in the current snapshot. However, delete files are not applied, and so in some cases partitions may be shown even though all their data rows are marked deleted by delete files.


### Positional Delete Files [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#positional-delete-files "Permanent link")

To show all positional delete files from the current snapshot of table:

```
SELECT * from prod.db.table.position_deletes;
```

| file\_path | pos | row | partition | spec\_id | delete\_file\_path |
| --- | --- | --- | --- | --- | --- |
| s3:/.../table/data/00042-3-a9aa8b24-20bc-4d56-93b0-6b7675782bb5-00001.parquet | 1 | 0 | {20211001, 11} | 0 | s3:/.../table/data/00191-1933-25e9f2f3-d863-4a69-a5e1-f9aeeebe60bb-00001-deletes.parquet |

### All Metadata Tables [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#all-metadata-tables "Permanent link")

These tables are unions of the metadata tables specific to the current snapshot, and return metadata across all snapshots.

Danger

The "all" metadata tables may produce more than one row per data file or manifest file because metadata files may be part of more than one table snapshot.

#### All Data Files [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#all-data-files "Permanent link")

To show all of the table's data files and each file's metadata:

```
SELECT * FROM prod.db.table.all_data_files;
```

| content | file\_path | file\_format | spec\_id | partition | record\_count | file\_size\_in\_bytes | column\_sizes | value\_counts | null\_value\_counts | nan\_value\_counts | lower\_bounds | upper\_bounds | key\_metadata | split\_offsets | equality\_ids | sort\_order\_id | readable\_metrics |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | s3://.../dt=20210102/00000-0-756e2512-49ae-45bb-aae3-c0ca475e7879-00001.parquet | PARQUET | 0 | {20210102} | 14 | 2444 | {1 -> 94, 2 -> 17} | {1 -> 14, 2 -> 14} | {1 -> 0, 2 -> 0} | {} | {1 -> 1, 2 -> 20210102} | {1 -> 2, 2 -> 20210102} | null | \[4\] | null | 0 | {"id":{"column\_size":94,"value\_count":14,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":2},"data":{"column\_size":17,"value\_count":14,"null\_value\_count": 0,"nan\_value\_count":null,"lower\_bound":20210102,"upper\_bound":20210102}} |
| 0 | s3://.../dt=20210103/00000-0-26222098-032f-472b-8ea5-651a55b21210-00001.parquet | PARQUET | 0 | {20210103} | 14 | 2444 | {1 -> 94, 2 -> 17} | {1 -> 14, 2 -> 14} | {1 -> 0, 2 -> 0} | {} | {1 -> 1, 2 -> 20210103} | {1 -> 3, 2 -> 20210103} | null | \[4\] | null | 0 | {"id":{"column\_size":94,"value\_count":14,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":3},"data":{"column\_size":17,"value\_count":14,"null\_value\_count": 0,"nan\_value\_count":null,"lower\_bound":20210103,"upper\_bound":20210103}} |
| 0 | s3://.../dt=20210104/00000-0-a3bb1927-88eb-4f1c-bc6e-19076b0d952e-00001.parquet | PARQUET | 0 | {20210104} | 14 | 2444 | {1 -> 94, 2 -> 17} | {1 -> 14, 2 -> 14} | {1 -> 0, 2 -> 0} | {} | {1 -> 1, 2 -> 20210104} | {1 -> 3, 2 -> 20210104} | null | \[4\] | null | 0 | {"id":{"column\_size":94,"value\_count":14,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":3},"data":{"column\_size":17,"value\_count":14,"null\_value\_count": 0,"nan\_value\_count":null,"lower\_bound":20210104,"upper\_bound":20210104}} |

#### All Delete Files [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#all-delete-files "Permanent link")

To show the table's delete files and each file's metadata from all the snapshots:

```
SELECT * FROM prod.db.table.all_delete_files;
```

| content | file\_path | file\_format | spec\_id | partition | record\_count | file\_size\_in\_bytes | column\_sizes | value\_counts | null\_value\_counts | nan\_value\_counts | lower\_bounds | upper\_bounds | key\_metadata | split\_offsets | equality\_ids | sort\_order\_id | readable\_metrics |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | s3:/.../table/data/00081-4-a9aa8b24-20bc-4d56-93b0-6b7675782bb5-00001-deletes.parquet | PARQUET | 0 | {20210102} | 1 | 1560 | {2147483545:46,2147483546:152} | {2147483545:1,2147483546:1} | {2147483545:0,2147483546:0} | {} | {2147483545:,2147483546:s3:/.../table/data/00000-0-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet} | {2147483545:,2147483546:s3:/.../table/data/00000-0-f9709213-22ca-4196-8733-5cb15d2afeb9-00001.parquet} | NULL | \[4\] | NULL | NULL | {"data":{"column\_size":null,"value\_count":null,"null\_value\_count":null,"nan\_value\_count":null,"lower\_bound":null,"upper\_bound":null},"id":{"column\_size":null,"value\_count":null,"null\_value\_count":null,"nan\_value\_count":null,"lower\_bound":null,"upper\_bound":null}} |
| 2 | s3:/.../table/data/00047-25-833044d0-127b-415c-b874-038a4f978c29-00612.parquet | PARQUET | 0 | {20210103} | 126506 | 28613985 | {100:135377,101:11314} | {100:126506,101:126506} | {100:105434,101:11} | {} | {100:0,101:17} | {100:404455227527,101:23} | NULL | NULL | \[1\] | 0 | {"id":{"column\_size":135377,"value\_count":126506,"null\_value\_count":105434,"nan\_value\_count":null,"lower\_bound":0,"upper\_bound":404455227527},"data":{"column\_size":11314,"value\_count":126506,"null\_value\_count": 11,"nan\_value\_count":null,"lower\_bound":17,"upper\_bound":23}} |

#### All Entries [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#all-entries "Permanent link")

To show the table's manifest entries from all the snapshots for both data and delete files:

```
SELECT * FROM prod.db.table.all_entries;
```

| status | snapshot\_id | sequence\_number | file\_sequence\_number | data\_file | readable\_metrics |
| --- | --- | --- | --- | --- | --- |
| 2 | 57897183625154 | 0 | 0 | {"content":0,"file\_path":"s3:/.../table/data/00047-25-833044d0-127b-415c-b874-038a4f978c29-00612.parquet","file\_format":"PARQUET","spec\_id":0,"record\_count":15,"file\_size\_in\_bytes":473,"column\_sizes":{1:103},"value\_counts":{1:15},"null\_value\_counts":{1:0},"nan\_value\_counts":{},"lower\_bounds":{1:},"upper\_bounds":{1:},"key\_metadata":null,"split\_offsets":\[4\],"equality\_ids":null,"sort\_order\_id":0} | {"c1":{"column\_size":103,"value\_count":15,"null\_value\_count":0,"nan\_value\_count":null,"lower\_bound":1,"upper\_bound":3}} |

#### All Manifests [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#all-manifests "Permanent link")

To show all of the table's manifest files:

```
SELECT * FROM prod.db.table.all_manifests;
```

| content | path | length | partition\_spec\_id | added\_snapshot\_id | added\_data\_files\_count | existing\_data\_files\_count | deleted\_data\_files\_count | added\_delete\_files\_count | existing\_delete\_files\_count | deleted\_delete\_files\_count | partition\_summaries | reference\_snapshot\_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | s3://.../metadata/a85f78c5-3222-4b37-b7e4-faf944425d48-m0.avro | 6376 | 0 | 6272782676904868561 | 2 | 0 | 0 | 0 | 0 | 0 | \[{false, false, 20210101, 20210101}\] | 57897183625154 |

Note:

1. Fields within `partition_summaries` column of the manifests table correspond to `field_summary` structs within [manifest list](https://iceberg.apache.org/spec/#manifest-lists), with the following order:
   - `contains_null`
   - `contains_nan`
   - `lower_bound`
   - `upper_bound`
2. `contains_nan` could return null, which indicates that this information is not available from the file's metadata.
    This usually occurs when reading from V1 table, where `contains_nan` is not populated.

### References [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#references "Permanent link")

To show a table's known snapshot references:

```
SELECT * FROM prod.db.table.refs;
```

| name | type | snapshot\_id | max\_reference\_age\_in\_ms | min\_snapshots\_to\_keep | max\_snapshot\_age\_in\_ms |
| --- | --- | --- | --- | --- | --- |
| main | BRANCH | 4686954189838128572 | 10 | 20 | 30 |
| testTag | TAG | 4686954189838128572 | 10 | null | null |

### Inspecting with DataFrames [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#inspecting-with-dataframes "Permanent link")

Metadata tables can be loaded using the DataFrameReader API:

```
// named metastore table
spark.read.format("iceberg").load("db.table.files")
// Hadoop path table
spark.read.format("iceberg").load("hdfs://nn:8020/path/to/table#files")
```

### Time Travel with Metadata Tables [🔗](https://iceberg.apache.org/docs/latest/spark-queries/\#time-travel-with-metadata-tables "Permanent link")

To inspect a tables's metadata with the time travel feature:

```
-- get the table's file manifests at timestamp Sep 20, 2021 08:00:00
SELECT * FROM prod.db.table.manifests TIMESTAMP AS OF '2021-09-20 08:00:00';

-- get the table's partitions with snapshot id 10963874102873L
SELECT * FROM prod.db.table.partitions VERSION AS OF 10963874102873;
```

Metadata tables can also be inspected with time travel using the DataFrameReader API:

```
// load the table's file metadata at snapshot-id 10963874102873 as DataFrame
spark.read.format("iceberg").option("snapshot-id", 10963874102873L).load("db.table.files")
```

Back to top