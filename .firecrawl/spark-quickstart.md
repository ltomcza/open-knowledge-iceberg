[Skip to content](https://iceberg.apache.org/spark-quickstart/#docker-compose)

# Spark

This guide will get you up and running with Apache Iceberg™ using Apache Spark™, including sample code to
highlight some powerful features. You can learn more about Iceberg's Spark runtime by checking out the [Spark](https://iceberg.apache.org/docs/latest/spark-ddl/) section.

- [Docker-Compose](https://iceberg.apache.org/spark-quickstart/#docker-compose)
- [Creating a table](https://iceberg.apache.org/spark-quickstart/#creating-a-table)
- [Writing Data to a Table](https://iceberg.apache.org/spark-quickstart/#writing-data-to-a-table)
- [Reading Data from a Table](https://iceberg.apache.org/spark-quickstart/#reading-data-from-a-table)
- [Adding A Catalog](https://iceberg.apache.org/spark-quickstart/#adding-a-catalog)
- [Next Steps](https://iceberg.apache.org/spark-quickstart/#next-steps)

### Docker-Compose [🔗](https://iceberg.apache.org/spark-quickstart/\#docker-compose "Permanent link")

The fastest way to get started is to use a docker-compose file that uses the [tabulario/spark-iceberg](https://hub.docker.com/r/tabulario/spark-iceberg) image
which contains a local Spark cluster with a configured Iceberg catalog. To use this, you'll need to install the [Docker CLI](https://docs.docker.com/get-docker/) as well as the [Docker Compose CLI](https://github.com/docker/compose-cli/blob/main/INSTALL.md).

Once you have those, save the yaml below into a file named `docker-compose.yml`:

```
services:
  spark-iceberg:
    image: tabulario/spark-iceberg
    container_name: spark-iceberg
    build: spark/
    networks:
      iceberg_net:
    depends_on:
      - rest
      - minio
    volumes:
      - ./warehouse:/home/iceberg/warehouse
      - ./notebooks:/home/iceberg/notebooks/notebooks
    environment:
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - AWS_REGION=us-east-1
    ports:
      - 8888:8888
      - 8080:8080
      - 10000:10000
      - 10001:10001
  rest:
    image: apache/iceberg-rest-fixture
    container_name: iceberg-rest
    networks:
      iceberg_net:
    ports:
      - 8181:8181
    environment:
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - AWS_REGION=us-east-1
      - CATALOG_WAREHOUSE=s3://warehouse/
      - CATALOG_IO__IMPL=org.apache.iceberg.aws.s3.S3FileIO
      - CATALOG_S3_ENDPOINT=http://minio:9000
  minio:
    image: minio/minio
    container_name: minio
    environment:
      - MINIO_ROOT_USER=admin
      - MINIO_ROOT_PASSWORD=password
      - MINIO_DOMAIN=minio
    networks:
      iceberg_net:
        aliases:
          - warehouse.minio
    ports:
      - 9001:9001
      - 9000:9000
    command: ["server", "/data", "--console-address", ":9001"]
  mc:
    depends_on:
      - minio
    image: minio/mc
    container_name: mc
    networks:
      iceberg_net:
    environment:
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - AWS_REGION=us-east-1
    entrypoint: |
      /bin/sh -c "
      until (/usr/bin/mc alias set minio http://minio:9000 admin password) do echo '...waiting...' && sleep 1; done;
      /usr/bin/mc rm -r --force minio/warehouse;
      /usr/bin/mc mb minio/warehouse;
      /usr/bin/mc policy set public minio/warehouse;
      tail -f /dev/null
      "
networks:
  iceberg_net:
```

Next, start up the docker containers with this command:

```
docker-compose up
```

You can then run any of the following commands to start a Spark session.

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_1_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_1_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_1_3)

```
docker exec -it spark-iceberg spark-sql
```

```
docker exec -it spark-iceberg spark-shell
```

```
docker exec -it spark-iceberg pyspark
```

Note

You can also use the notebook server available at [http://localhost:8888](http://localhost:8888/)

### Creating a table [🔗](https://iceberg.apache.org/spark-quickstart/\#creating-a-table "Permanent link")

To create your first Iceberg table in Spark, run a [`CREATE TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table) command. Let's create a table
using `demo.nyc.taxis` where `demo` is the catalog name, `nyc` is the database name, and `taxis` is the table name.

First, create the database if it doesn't already exist:

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_2_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_2_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_2_3)

```
CREATE DATABASE IF NOT EXISTS demo.nyc;
```

```
spark.sql("CREATE DATABASE IF NOT EXISTS demo.nyc")
```

```
spark.sql("CREATE DATABASE IF NOT EXISTS demo.nyc")
```

Then create the table:

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_3_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_3_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_3_3)

```
CREATE TABLE demo.nyc.taxis
(
  vendor_id bigint,
  trip_id bigint,
  trip_distance float,
  fare_amount double,
  store_and_fwd_flag string
)
PARTITIONED BY (vendor_id);
```

```
import org.apache.spark.sql.types._
import org.apache.spark.sql.Row
val schema = StructType( Array(
    StructField("vendor_id", LongType,true),
    StructField("trip_id", LongType,true),
    StructField("trip_distance", FloatType,true),
    StructField("fare_amount", DoubleType,true),
    StructField("store_and_fwd_flag", StringType,true)
))
val df = spark.createDataFrame(spark.sparkContext.emptyRDD[Row],schema)
df.writeTo("demo.nyc.taxis").create()
```

```
from pyspark.sql.types import DoubleType, FloatType, LongType, StructType,StructField, StringType
schema = StructType([\
  StructField("vendor_id", LongType(), True),\
  StructField("trip_id", LongType(), True),\
  StructField("trip_distance", FloatType(), True),\
  StructField("fare_amount", DoubleType(), True),\
  StructField("store_and_fwd_flag", StringType(), True)\
])

df = spark.createDataFrame([], schema)
df.writeTo("demo.nyc.taxis").create()
```

Iceberg catalogs support the full range of SQL DDL commands, including:

- [`CREATE TABLE ... PARTITIONED BY`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table)
- [`CREATE TABLE ... AS SELECT`](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table--as-select)
- [`ALTER TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#alter-table)
- [`DROP TABLE`](https://iceberg.apache.org/docs/latest/spark-ddl/#drop-table)

### Writing Data to a Table [🔗](https://iceberg.apache.org/spark-quickstart/\#writing-data-to-a-table "Permanent link")

Once your table is created, you can insert records.

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_4_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_4_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_4_3)

```
INSERT INTO demo.nyc.taxis
VALUES (1, 1000371, 1.8, 15.32, 'N'), (2, 1000372, 2.5, 22.15, 'N'), (2, 1000373, 0.9, 9.01, 'N'), (1, 1000374, 8.4, 42.13, 'Y');
```

```
import org.apache.spark.sql.Row

val schema = spark.table("demo.nyc.taxis").schema
val data = Seq(
    Row(1: Long, 1000371: Long, 1.8f: Float, 15.32: Double, "N": String),
    Row(2: Long, 1000372: Long, 2.5f: Float, 22.15: Double, "N": String),
    Row(2: Long, 1000373: Long, 0.9f: Float, 9.01: Double, "N": String),
    Row(1: Long, 1000374: Long, 8.4f: Float, 42.13: Double, "Y": String)
)
val df = spark.createDataFrame(spark.sparkContext.parallelize(data), schema)
df.writeTo("demo.nyc.taxis").append()
```

```
schema = spark.table("demo.nyc.taxis").schema
data = [\
    (1, 1000371, 1.8, 15.32, "N"),\
    (2, 1000372, 2.5, 22.15, "N"),\
    (2, 1000373, 0.9, 9.01, "N"),\
    (1, 1000374, 8.4, 42.13, "Y")\
  ]
df = spark.createDataFrame(data, schema)
df.writeTo("demo.nyc.taxis").append()
```

### Reading Data from a Table [🔗](https://iceberg.apache.org/spark-quickstart/\#reading-data-from-a-table "Permanent link")

To read a table, simply use the Iceberg table's name.

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_5_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_5_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_5_3)

```
SELECT * FROM demo.nyc.taxis;
```

```
val df = spark.table("demo.nyc.taxis").show()
```

```
df = spark.table("demo.nyc.taxis").show()
```

### Adding A Catalog [🔗](https://iceberg.apache.org/spark-quickstart/\#adding-a-catalog "Permanent link")

Iceberg has several catalog back-ends that can be used to track tables, like JDBC, Hive MetaStore and Glue.
Catalogs are configured using properties under `spark.sql.catalog.(catalog_name)`. In this guide,
we use JDBC, but you can follow these instructions to configure other catalog types. To learn more, check out
the [Catalog](https://iceberg.apache.org/docs/latest/spark-configuration/#catalogs) page in the Spark section.

This configuration creates a path-based catalog named `local` for tables under `$PWD/warehouse` and adds support for Iceberg tables to Spark's built-in catalog.

[CLI](https://iceberg.apache.org/spark-quickstart/#__tabbed_6_1)[spark-defaults.conf](https://iceberg.apache.org/spark-quickstart/#__tabbed_6_2)

```
spark-sql --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0\
    --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
    --conf spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog \
    --conf spark.sql.catalog.spark_catalog.type=hive \
    --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
    --conf spark.sql.catalog.local.type=hadoop \
    --conf spark.sql.catalog.local.warehouse=$PWD/warehouse \
    --conf spark.sql.defaultCatalog=local
```

```
spark.jars.packages                                  org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0
spark.sql.extensions                                 org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalog.spark_catalog                      org.apache.iceberg.spark.SparkSessionCatalog
spark.sql.catalog.spark_catalog.type                 hive
spark.sql.catalog.local                              org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.local.type                         hadoop
spark.sql.catalog.local.warehouse                    $PWD/warehouse
spark.sql.defaultCatalog                             local
```

Note

If your Iceberg catalog is not set as the default catalog, you will have to switch to it by executing `USE local;`

### Next steps [🔗](https://iceberg.apache.org/spark-quickstart/\#next-steps "Permanent link")

#### Adding Iceberg to Spark [🔗](https://iceberg.apache.org/spark-quickstart/\#adding-iceberg-to-spark "Permanent link")

If you already have a Spark environment, you can add Iceberg, using the `--packages` option.

[SparkSQL](https://iceberg.apache.org/spark-quickstart/#__tabbed_7_1)[Spark-Shell](https://iceberg.apache.org/spark-quickstart/#__tabbed_7_2)[PySpark](https://iceberg.apache.org/spark-quickstart/#__tabbed_7_3)

```
spark-sql --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0
```

```
spark-shell --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0
```

```
pyspark --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0
```

Note

If you want to include Iceberg in your Spark installation, add the Iceberg Spark runtime to Spark's `jars` folder.
You can download the runtime from the [Releases](https://iceberg.apache.org/releases/) page.

#### Learn More [🔗](https://iceberg.apache.org/spark-quickstart/\#learn-more "Permanent link")

Now that you're up and running with Iceberg and Spark, check out the [Iceberg-Spark docs](https://iceberg.apache.org/docs/latest/spark-ddl/) to learn more!

Back to top