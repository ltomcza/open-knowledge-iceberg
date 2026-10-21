[Skip to content](https://iceberg.apache.org/docs/latest/spark-getting-started/#getting-started)

# Getting Started [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#getting-started "Permanent link")

The latest version of Iceberg is [1.11.0](https://iceberg.apache.org/releases/).

Spark is currently the most feature-rich compute engine for Iceberg operations.
We recommend you to get started with Spark to understand Iceberg concepts and features with examples.
You can also view documentations of using Iceberg with other compute engine under the [Multi-Engine Support](https://iceberg.apache.org/multi-engine-support/) page.

## Using Iceberg in Spark [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#using-iceberg-in-spark "Permanent link")

To use Iceberg in a Spark shell, use the `--packages` option:

```
spark-shell --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0
```

Info

If you want to include Iceberg in your Spark installation, add the [`iceberg-spark-runtime-4.1_2.13` Jar](https://search.maven.org/remotecontent?filepath=org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/1.11.0/iceberg-spark-runtime-4.1_2.13-1.11.0.jar) to Spark's `jars` folder.

### Adding catalogs [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#adding-catalogs "Permanent link")

Iceberg comes with [catalogs](https://iceberg.apache.org/docs/latest/spark-configuration/#catalogs) that enable SQL commands to manage tables and load them by name. Catalogs are configured using properties under `spark.sql.catalog.(catalog_name)`.

This command creates a path-based catalog named `local` for tables under `$PWD/warehouse` and adds support for Iceberg tables to Spark's built-in catalog:

```
spark-sql --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0\
    --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
    --conf spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog \
    --conf spark.sql.catalog.spark_catalog.type=hive \
    --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
    --conf spark.sql.catalog.local.type=hadoop \
    --conf spark.sql.catalog.local.warehouse=$PWD/warehouse
```

### Creating a table [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#creating-a-table "Permanent link")

To create your first Iceberg table in Spark, use the `spark-sql` shell or `spark.sql(...)` to run a [`CREATE TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table) command:

```
-- local is the path-based catalog defined above
CREATE TABLE local.db.table (id bigint, data string) USING iceberg;
CREATE TABLE source (id bigint, data string) USING parquet;
CREATE TABLE updates (id bigint, data string) USING parquet;
```

Iceberg catalogs support the full range of SQL DDL commands, including:

- [`CREATE TABLE ... PARTITIONED BY`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table)
- [`CREATE TABLE ... AS SELECT`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table-as-select)
- [`ALTER TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#alter-table)
- [`DROP TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#drop-table)

### Writing [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#writing "Permanent link")

Once your table is created, insert data using [`INSERT INTO`](https://iceberg.apache.org/docs/latest/spark-writes/#insert-into):

```
INSERT INTO local.db.table VALUES (1, 'a'), (2, 'b'), (3, 'c');
INSERT INTO source VALUES (10, 'd'), (11, 'ee');
INSERT INTO updates VALUES (1, 'x'), (2, 'x'), (4, 'z');
INSERT INTO local.db.table SELECT id, data FROM source WHERE length(data) = 1;
```

Iceberg also adds row-level SQL updates to Spark, [`MERGE INTO`](https://iceberg.apache.org/docs/latest/spark-writes/#merge-into) and [`DELETE FROM`](https://iceberg.apache.org/docs/latest/spark-writes/#delete-from):

```
MERGE INTO local.db.table t USING (SELECT * FROM updates) u ON t.id = u.id
WHEN MATCHED THEN UPDATE SET t.data = u.data
WHEN NOT MATCHED THEN INSERT *;
```

Iceberg supports writing DataFrames using the new [v2 DataFrame write API](https://iceberg.apache.org/docs/latest/spark-writes/#writing-with-dataframes):

```
spark.table("source").select("id", "data")
     .writeTo("local.db.table").append()
```

The old `write` API is supported, but _not_ recommended.

### Reading [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#reading "Permanent link")

To read with SQL, use the Iceberg table's name in a `SELECT` query:

```
SELECT count(1) as count, data
FROM local.db.table
GROUP BY data;
```

SQL is also the recommended way to [inspect tables](https://iceberg.apache.org/docs/latest/spark-queries/#inspecting-tables). To view all snapshots in a table, use the `snapshots` metadata table:

```
SELECT * FROM local.db.table.snapshots;
```

```
+-------------------------+----------------+-----------+-----------+----------------------------------------------------+-----+
| committed_at            | snapshot_id    | parent_id | operation | manifest_list                                      | ... |
+-------------------------+----------------+-----------+-----------+----------------------------------------------------+-----+
| 2019-02-08 03:29:51.215 | 57897183625154 | null      | append    | s3://.../table/metadata/snap-57897183625154-1.avro | ... |
|                         |                |           |           |                                                    | ... |
|                         |                |           |           |                                                    | ... |
| ...                     | ...            | ...       | ...       | ...                                                | ... |
+-------------------------+----------------+-----------+-----------+----------------------------------------------------+-----+
```

[DataFrame reads](https://iceberg.apache.org/docs/latest/spark-queries/#querying-with-dataframes) are supported and can now reference tables by name using `spark.table`:

```
val df = spark.table("local.db.table")
df.count()
```

### Type compatibility [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#type-compatibility "Permanent link")

Spark and Iceberg support different set of types. Iceberg does the type conversion automatically, but not for all combinations,
so you may want to understand the type conversion in Iceberg in prior to design the types of columns in your tables.

#### Spark type to Iceberg type [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#spark-type-to-iceberg-type "Permanent link")

This type conversion table describes how Spark types are converted to the Iceberg types. The conversion applies on both creating Iceberg table and writing to Iceberg table via Spark.

| Spark | Iceberg | Notes |
| --- | --- | --- |
| boolean | boolean |  |
| short | integer |  |
| byte | integer |  |
| integer | integer |  |
| long | long |  |
| float | float |  |
| double | double |  |
| date | date |  |
| timestamp | timestamp with timezone |  |
| timestamp\_ntz | timestamp without timezone |  |
| char | string |  |
| varchar | string |  |
| string | string |  |
| binary | binary |  |
| decimal | decimal |  |
| struct | struct |  |
| array | list |  |
| map | map |  |

Info

The table is based on representing conversion during creating table. In fact, broader supports are applied on write. Here're some points on write:

- Iceberg numeric types (`integer`, `long`, `float`, `double`, `decimal`) support promotion during writes. e.g. You can write Spark types `short`, `byte`, `integer`, `long` to Iceberg type `long`.
- You can write to Iceberg `fixed` type using Spark `binary` type. Note that assertion on the length will be performed.

#### Iceberg type to Spark type [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#iceberg-type-to-spark-type "Permanent link")

This type conversion table describes how Iceberg types are converted to the Spark types. The conversion applies on reading from Iceberg table via Spark.

| Iceberg | Spark | Note |
| --- | --- | --- |
| boolean | boolean |  |
| integer | integer |  |
| long | long |  |
| float | float |  |
| double | double |  |
| date | date |  |
| time |  | Not supported |
| timestamp with timezone | timestamp |  |
| timestamp without timezone | timestamp\_ntz |  |
| string | string |  |
| uuid | string |  |
| fixed | binary |  |
| binary | binary |  |
| decimal | decimal |  |
| struct | struct |  |
| list | array |  |
| map | map |  |
| nanosecond timestamp |  | Not supported |
| nanosecond timestamp with timezone |  | Not supported |
| unknown | null | Spark 4.0+ |
| variant | variant | Spark 4.0+ |
| geometry |  | Not supported |
| geography |  | Not supported |

### Next steps [🔗](https://iceberg.apache.org/docs/latest/spark-getting-started/\#next-steps "Permanent link")

Next, you can learn more about Iceberg tables in Spark:

- [DDL commands](https://iceberg.apache.org/docs/latest/spark-ddl/): `CREATE`, `ALTER`, and `DROP`
- [Querying data](https://iceberg.apache.org/docs/latest/spark-queries/): `SELECT` queries and metadata tables
- [Writing data](https://iceberg.apache.org/docs/latest/spark-writes/): `INSERT INTO` and `MERGE INTO`
- [Maintaining tables](https://iceberg.apache.org/docs/latest/spark-procedures/) with stored procedures

Back to top