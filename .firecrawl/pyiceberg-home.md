[Skip to content](https://py.iceberg.apache.org/#getting-started-with-pyiceberg)

# Getting started with PyIceberg [¶](https://py.iceberg.apache.org/\#getting-started-with-pyiceberg "Permanent link")

PyIceberg is a Python implementation for accessing Iceberg tables, without the need of a JVM.

## Installation [¶](https://py.iceberg.apache.org/\#installation "Permanent link")

Before installing PyIceberg, make sure that you're on an up-to-date version of `pip`:

```
pip install --upgrade pip
```

You can install the latest release version from pypi:

```
pip install "pyiceberg[s3fs,hive]"
```

You can mix and match optional dependencies depending on your needs:

| Key | Description: |
| --- | --- |
| hive | Support for the Hive metastore |
| hive-kerberos | Support for Hive metastore in Kerberos environment |
| glue | Support for AWS Glue |
| dynamodb | Support for AWS DynamoDB |
| bigquery | Support for Google Cloud BigQuery |
| sql-postgres | Support for SQL Catalog backed by Postgresql |
| sql-sqlite | Support for SQL Catalog backed by SQLite |
| pyarrow | PyArrow as a FileIO implementation to interact with the object store |
| pandas | Installs both PyArrow and Pandas |
| duckdb | Installs both PyArrow and DuckDB |
| ray | Installs PyArrow, Pandas, and Ray |
| bodo | Installs Bodo |
| daft | Installs Daft |
| polars | Installs Polars |
| s3fs | S3FS as a FileIO implementation to interact with the object store |
| adlfs | ADLFS as a FileIO implementation to interact with the object store |
| snappy | Support for snappy Avro compression |
| gcsfs | GCSFS as a FileIO implementation to interact with the object store |
| rest-sigv4 | Support for generating AWS SIGv4 authentication headers for REST Catalogs |
| pyiceberg-core | Installs iceberg-rust powered core |
| datafusion | Installs both PyArrow and Apache DataFusion |
| hf | Support for Hugging Face Hub |
| gcp-auth | Support for Google Cloud authentication |
| entra-auth | Support for Azure Entra authentication |

You either need to install `s3fs`, `adlfs`, `gcsfs`, or `pyarrow` to be able to fetch files from an object store.

## Connecting to a catalog [¶](https://py.iceberg.apache.org/\#connecting-to-a-catalog "Permanent link")

Iceberg leverages the [catalog to have one centralized place to organize the tables](https://iceberg.apache.org/terms/#catalog). This can be a traditional Hive catalog to store your Iceberg tables next to the rest, a vendor solution like the AWS Glue catalog, or an implementation of Icebergs' own [REST protocol](https://github.com/apache/iceberg/tree/main/open-api). Checkout the [configuration](https://py.iceberg.apache.org/configuration/) page to find all the configuration details.

For the sake of demonstration, we'll configure the catalog to use the `SqlCatalog` implementation, which will store information in a local `sqlite` database. We'll also configure the catalog to store data files in the local filesystem instead of an object store. This should not be used in production due to the limited scalability.

Create a temporary location for Iceberg:

```
mkdir /tmp/warehouse
```

Open a Python 3 REPL to set up the catalog:

```
from pyiceberg.catalog import load_catalog

warehouse_path = "/tmp/warehouse"
catalog = load_catalog(
    "default",
    **{
        'type': 'sql',
        "uri": f"sqlite:///{warehouse_path}/pyiceberg_catalog.db",
        "warehouse": f"file://{warehouse_path}",
    },
)
```

The `sql` catalog works for testing locally without needing another service. If you want to try out another catalog, please [check out the configuration](https://py.iceberg.apache.org/configuration/#catalogs).

## Write a PyArrow dataframe [¶](https://py.iceberg.apache.org/\#write-a-pyarrow-dataframe "Permanent link")

Let's take the Taxi dataset, and write this to an Iceberg table.

First download one month of data:

```
curl https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-01.parquet -o /tmp/yellow_tripdata_2023-01.parquet
```

Load it into your PyArrow dataframe:

```
import pyarrow.parquet as pq

df = pq.read_table("/tmp/yellow_tripdata_2023-01.parquet")
```

Create a new Iceberg table:

```
catalog.create_namespace("default")

table = catalog.create_table(
    "default.taxi_dataset",
    schema=df.schema,
)
```

Append the dataframe to the table:

```
table.append(df)
len(table.scan().to_arrow())
```

3066766 rows have been written to the table.

Now generate a tip-per-mile feature to train the model on:

```
import pyarrow.compute as pc

df = df.append_column("tip_per_mile", pc.divide(df["tip_amount"], df["trip_distance"]))
```

Evolve the schema of the table with the new column:

```
with table.update_schema() as update_schema:
    update_schema.union_by_name(df.schema)
```

And now we can write the new dataframe to the Iceberg table:

```
table.overwrite(df)
print(table.scan().to_arrow())
```

And the new column is there:

```
taxi_dataset(
  1: VendorID: optional long,
  2: tpep_pickup_datetime: optional timestamp,
  3: tpep_dropoff_datetime: optional timestamp,
  4: passenger_count: optional double,
  5: trip_distance: optional double,
  6: RatecodeID: optional double,
  7: store_and_fwd_flag: optional string,
  8: PULocationID: optional long,
  9: DOLocationID: optional long,
  10: payment_type: optional long,
  11: fare_amount: optional double,
  12: extra: optional double,
  13: mta_tax: optional double,
  14: tip_amount: optional double,
  15: tolls_amount: optional double,
  16: improvement_surcharge: optional double,
  17: total_amount: optional double,
  18: congestion_surcharge: optional double,
  19: airport_fee: optional double,
  20: tip_per_mile: optional double
),
```

And we can see that 2371784 rows have a tip-per-mile:

```
df = table.scan(row_filter="tip_per_mile > 0").to_arrow()
len(df)
```

### Explore Iceberg data and metadata files [¶](https://py.iceberg.apache.org/\#explore-iceberg-data-and-metadata-files "Permanent link")

Since the catalog was configured to use the local filesystem, we can explore how Iceberg saved data and metadata files from the above operations.

```
find /tmp/warehouse/
```

## Try it yourself with Jupyter Notebooks [¶](https://py.iceberg.apache.org/\#try-it-yourself-with-jupyter-notebooks "Permanent link")

PyIceberg provides Jupyter notebooks for hands-on experimentation with the examples above and more. Check out the [Notebooks for Experimentation](https://py.iceberg.apache.org/contributing/#notebooks-for-experimentation) guide.

## More details [¶](https://py.iceberg.apache.org/\#more-details "Permanent link")

For the details, please check the [CLI](https://py.iceberg.apache.org/cli/) or [Python API](https://py.iceberg.apache.org/api/) page.

Back to top