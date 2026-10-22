---
type: PySpark Guide
title: Using Iceberg Tables Through Spark Connect
description: How to configure an Iceberg-enabled Spark Connect server and drive it from a thin pyspark-client, including the config-must-be-server-side constraint.
aliases: [iceberg spark connect, pyspark client sc://, spark connect iceberg catalog, remote spark session iceberg, start-connect-server iceberg]
tags: [pyspark, spark-connect, catalog, configuration, client-server]
timestamp: 2026-10-22T00:00:00Z
resource: https://spark.apache.org/docs/latest/spark-connect-overview.html
---

# Retrieval Notes

Read this when you need to drive Iceberg tables from a **thin client** — a notebook, IDE, application
server, or orchestrator process — that should not embed a full Spark driver JVM, or when you're
consolidating many client applications onto one shared, centrally-upgraded Spark cluster. If you just
need ordinary local/cluster PySpark setup, see [/pyspark/setup-and-configuration.md](/pyspark/setup-and-configuration.md)
instead — Spark Connect is an alternative *deployment* mode, not a different way of writing Iceberg
SQL or DataFrame code. For a runnable walkthrough, see [/tutorials/09-spark-connect.md](/tutorials/09-spark-connect.md).

# Summary

- **Spark Connect** (Spark 3.4+) is a decoupled client-server architecture: a thin gRPC client sends
  DataFrame operations as unresolved logical plans to a remote Spark server, which parses, plans, and
  executes them with the normal Catalyst engine and streams Arrow-encoded results back.
- Because Iceberg's SQL support (`CREATE TABLE ... USING iceberg`, `MERGE INTO`, `ALTER TABLE ... ADD
  PARTITION FIELD`, `CALL system.*` procedures) is implemented as Catalyst-level parser/analyzer
  extensions, it all executes **on the server** — a Spark Connect client does not need any
  Iceberg-specific code path once the server is configured correctly.
- **The critical constraint:** a Spark Connect client has no access to the server's *static*
  configuration or `SparkContext`. This means `spark.jars.packages`, `spark.sql.extensions`, and every
  `spark.sql.catalog.*` property **must be set when the Spark Connect server is started** (via
  `start-connect-server.sh` flags or `spark-defaults.conf`) — a client cannot register or reconfigure
  an Iceberg catalog after connecting.
- Client install is a **different pip package**: `pip install pyspark-client==<version>` (not
  `pyspark`), matched to the server's Spark version. Connect with
  `SparkSession.builder.remote("sc://host:port").getOrCreate()` or by setting the `SPARK_REMOTE`
  env var; the default port is `15002`.
- Unsupported/limited under Spark Connect regardless of Iceberg: raw `RDD`/`SparkContext` APIs, and
  UDFs need extra artifact-upload setup. These are Spark Connect limitations, not Iceberg ones.

# Why Use Spark Connect with Iceberg

Spark Connect exists to solve multi-tenant operational problems with classic PySpark: every client
process traditionally embeds its own Spark driver, so a misbehaving client can crash or destabilize
shared infrastructure, and upgrading Spark means coordinating every client's dependency. With Spark
Connect, one team runs and upgrades a Spark Connect server (with the Iceberg runtime and catalogs
configured once, centrally), and many lightweight clients — notebooks, microservices, an orchestrator's
worker processes — connect to it over gRPC without embedding a JVM at all. This is a natural fit for
Iceberg specifically because reads/writes/DDL are just Spark SQL and DataFrame operations, all of which
are planned and executed server-side.

# Setting Up the Server with Iceberg

Because the client cannot set static config, put every Iceberg-related setting on the server. Using the
same local Hadoop-catalog setup as the rest of this knowledge base's tutorials
(see [/pyspark/setup-and-configuration.md](/pyspark/setup-and-configuration.md)):

```bash
# From a full Spark distribution (has sbin/start-connect-server.sh)
./sbin/start-connect-server.sh \
  --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.12.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.local.type=hadoop \
  --conf spark.sql.catalog.local.warehouse=/tmp/warehouse \
  --conf spark.sql.defaultCatalog=local
```

`start-connect-server.sh` is built on the same launcher as `spark-submit`, so it accepts the same
`--packages`/`--conf`/`--jars` flags used for any other Iceberg-on-Spark setup — see
[/catalogs/index.md](/catalogs/index.md) for the equivalent flags for REST, Hive, Glue, Nessie, and JDBC
catalogs; every one of them works the same way here, just supplied at server start instead of client
connect time. The same settings can also live permanently in the server's `conf/spark-defaults.conf` so
you don't have to repeat them on every restart.

Stop the server with:

```bash
./sbin/stop-connect-server.sh
```

# Connecting a Client

Install the client package — note this is `pyspark-client`, not `pyspark`, and the two should not be
installed in the same environment:

```bash
pip install pyspark-client==4.1.0   # match the server's Spark version
```

Connect explicitly with the `remote(...)` builder method:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()

# Confirm you're actually on a Connect session:
print(type(spark))
# <class 'pyspark.sql.connect.session.SparkSession'>
```

Or point the shell at a server without code changes, via the environment variable:

```bash
export SPARK_REMOTE="sc://localhost:15002"
pyspark
```

For a remote/authenticated server behind a proxy, the connection string can carry a token:

```bash
export SPARK_REMOTE="sc://myhost.com:443/;token=ABCDEFG"
```

# Using Iceberg Through a Connect Session

Once connected, every Iceberg operation documented elsewhere in this knowledge base works identically —
there is no Iceberg-Connect-specific SQL syntax:

```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS db")
spark.sql("""
    CREATE TABLE IF NOT EXISTS local.db.taxis (
        vendor_id BIGINT, trip_id BIGINT, fare_amount DOUBLE
    ) USING iceberg PARTITIONED BY (vendor_id)
""")
spark.sql("INSERT INTO local.db.taxis VALUES (1, 1000371, 15.32)")
spark.table("local.db.taxis").show()

# MERGE INTO, procedures, and metadata tables all work the same way:
spark.sql("CALL local.system.rewrite_data_files('db.taxis')")
spark.sql("SELECT * FROM local.db.taxis.snapshots").show()
```

See [/pyspark/ddl-create-alter-tables.md](/pyspark/ddl-create-alter-tables.md),
[/pyspark/writing-data.md](/pyspark/writing-data.md),
[/pyspark/merge-into-and-row-level-operations.md](/pyspark/merge-into-and-row-level-operations.md), and
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) for full syntax references — everything in
those files applies unchanged under Spark Connect.

# Constraints and Gotchas

| Constraint | Why | What to do |
|---|---|---|
| Catalog/extension config can't be set from the client | Client has no access to static Spark config or `SparkContext` | Set `spark.sql.catalog.*`, `spark.sql.extensions`, and `spark.jars.packages` on the server (`start-connect-server.sh` flags or `spark-defaults.conf`) |
| `pyspark` and `pyspark-client` conflict | They're separate, incompatible packages providing the same `pyspark` module namespace | Use a dedicated virtualenv for Connect client code |
| Client/server version skew | Protocol compatibility is best within the same Spark line | Pin `pyspark-client==<version>` to match the server's Spark version |
| RDD APIs (`df.rdd`, `sc.parallelize`), `SparkContext`, and low-level Java/Scala catalog plugin classes | Spark Connect doesn't expose RDDs or the driver JVM to the client | Stay on DataFrame/SQL APIs, which is how you'd write Iceberg code anyway |
| UDFs | Python UDFs work by default (the server needs a compatible Python); Scala/Java client UDFs need a `ClassFinder` or artifact upload so the server can fetch the classes | Only relevant if you use UDFs inside Iceberg pipelines; plain SQL and built-in functions need no extra setup |
| Two SparkSessions can't coexist | A classic local `SparkSession` and a remote Connect `SparkSession` conflict in the same process | Call `.stop()` on any existing local session before creating a remote one |

# Citations

[1] [Spark Connect Overview](https://spark.apache.org/docs/latest/spark-connect-overview.html)
[2] [Quickstart: Spark Connect (PySpark docs)](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html)
[3] [Iceberg Spark Configuration — Catalogs and SQL Extensions](https://iceberg.apache.org/docs/latest/spark-configuration/)
[4] [Iceberg Spark Getting Started](https://iceberg.apache.org/docs/latest/spark-getting-started/)
