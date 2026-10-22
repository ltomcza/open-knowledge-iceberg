---
type: Tutorial
title: 9. Iceberg Through Spark Connect
description: Run an Iceberg-enabled Spark Connect server and drive it from a separate thin pyspark-client environment — the same table operations from tutorial 2, over gRPC instead of an embedded driver.
aliases: [spark connect iceberg tutorial, remote pyspark iceberg, pyspark-client iceberg walkthrough]
tags: [tutorial, pyspark, spark-connect, intermediate]
timestamp: 2026-10-22T00:00:00Z
difficulty: intermediate
---

# Prerequisites

- Completed [1. Environment Setup](/tutorials/01-environment-setup.md) and
  [2. Your First Table: Create, Insert, Read](/tutorials/02-first-table-crud.md) — this tutorial reuses
  the same `local` Hadoop-catalog config and `/tmp/warehouse` directory.
- A **full Spark distribution on disk** (not just `pip install pyspark`), because you need the
  `sbin/start-connect-server.sh` script. Download and extract it:

  ```bash
  curl -O https://archive.apache.org/dist/spark/spark-4.1.0/spark-4.1.0-bin-hadoop3.tgz
  tar -xvf spark-4.1.0-bin-hadoop3.tgz
  cd spark-4.1.0-bin-hadoop3
  ```

  (Check [the Spark downloads page](https://spark.apache.org/downloads.html) for the current release
  — `downloads.apache.org` only keeps current releases, older ones move to `archive.apache.org`.
  A pip-installed `pyspark` does **not** include `start-connect-server.sh`; with only pip PySpark, run
  `spark-submit --class org.apache.spark.sql.connect.service.SparkConnectServer` with the same flags as
  step 1 instead, as the Docker mapping in tutorial 1 describes.)
- Two separate terminals (and ideally two separate Python virtualenvs — see Common Pitfalls).

# What You'll Learn

- Why Iceberg's catalog and extension config has to be set on the **server**, not the client, under
  Spark Connect.
- How to start a local Spark Connect server pre-configured with Iceberg.
- How to connect a lightweight `pyspark-client` session and run the same table operations from
  tutorial 2 through it.

# Steps

## 1. Start the Spark Connect server with Iceberg configured

In your first terminal, from the extracted Spark distribution directory:

```bash
./sbin/start-connect-server.sh \
  --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.12.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.local.type=hadoop \
  --conf spark.sql.catalog.local.warehouse=/tmp/warehouse \
  --conf spark.sql.defaultCatalog=local
```

**Expected output:** the script starts the server **in the background** (via `spark-daemon.sh`) and
returns immediately, printing the path of its log file (`starting
org.apache.spark.sql.connect.service.SparkConnectServer, logging to ...`). Tail that log to watch Spark
resolve the Iceberg runtime jar (first run only) and start listening on port `15002`. To keep it in the
foreground instead, pass `--wait` as the first argument. Stop it later with
`./sbin/stop-connect-server.sh`. (Corrected 2026-10-22 — an earlier version said the script stays in
the foreground.)

## 2. Install the Spark Connect client in a separate environment

In your second terminal, create a fresh virtualenv so `pyspark-client` doesn't collide with any regular
`pyspark` install:

```bash
python -m venv connect-client-env
source connect-client-env/bin/activate   # Windows: connect-client-env\Scripts\activate
pip install pyspark-client==4.1.0
```

Use the same version number as your server's Spark distribution (check with
`./bin/spark-submit --version` in the first terminal if unsure).

## 3. Connect to the server

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()

print(type(spark))
```

**Expected output:**

```
<class 'pyspark.sql.connect.session.SparkSession'>
```

That confirms you're on a Connect session, not a local embedded one.

## 4. Run the same table operations as tutorial 2 — now over gRPC

```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS db")

spark.sql("""
    CREATE TABLE IF NOT EXISTS local.db.taxis (
        vendor_id BIGINT,
        trip_id BIGINT,
        fare_amount DOUBLE
    )
    USING iceberg
    PARTITIONED BY (vendor_id)
""")

spark.sql("""
    INSERT INTO local.db.taxis VALUES
    (1, 1000371, 15.32),
    (2, 1000372, 22.15)
""")

spark.table("local.db.taxis").show()
```

**Expected output:**

```
+---------+-------+-----------+
|vendor_id|trip_id|fare_amount|
+---------+-------+-----------+
|        1|1000371|      15.32|
|        2|1000372|      22.15|
+---------+-------+-----------+
```

Notice nothing about the SQL changed from tutorial 2 — the table was created, written, and read on the
remote server exactly as it would be locally, because Iceberg's SQL extensions are Catalyst-level and
execute server-side regardless of how the client connected.

## 5. Confirm DataFrame writes and stored procedures work too

```python
df = spark.createDataFrame([(1, 1000373, 9.01)], ["vendor_id", "trip_id", "fare_amount"])
df.writeTo("local.db.taxis").append()

spark.sql("CALL local.system.rewrite_data_files('db.taxis')").show()
spark.sql("SELECT snapshot_id, operation FROM local.db.taxis.snapshots").show()
```

**Expected output:** the `rewrite_data_files` call returns a summary row (rewritten/added file counts),
and the snapshots query lists the `append` and `replace` operations you just performed — the full
`CALL system.*` procedure reference in
[/pyspark/spark-procedures.md](/pyspark/spark-procedures.md) applies unchanged.

## 6. Shut down

In the client terminal:

```python
spark.stop()
```

In the server terminal (or from the Spark distribution directory in a new shell):

```bash
./sbin/stop-connect-server.sh
```

# Common Pitfalls

- **Setting catalog config on the client instead of the server.** If you try
  `SparkSession.builder.remote(...).config("spark.sql.catalog.local", ...)`, it will silently have no
  effect — Spark Connect clients cannot alter static configuration. All catalog/extension/package
  config belongs in the `start-connect-server.sh` command or `conf/spark-defaults.conf`, as in step 1.
- **Installing `pyspark` and `pyspark-client` in the same environment.** They provide conflicting
  versions of the `pyspark` module. Always isolate the Connect client in its own virtualenv (step 2).
- **Client/server version mismatch.** Pin `pyspark-client` to the same version as the server's Spark
  distribution; skew across minor versions can cause protocol errors.
- **Leaving a local `SparkSession` active.** If a classic (non-Connect) `SparkSession` already exists in
  your Python process, creating a remote one will fail or behave unexpectedly — call `.stop()` on it
  first, or simply use a fresh process/kernel for the client.
- **Forgetting the server is a separate long-running process.** Unlike `pyspark --packages ...` in
  earlier tutorials, the server here keeps running independently of any one client; multiple clients can
  connect to and disconnect from it without restarting it.

# Next Steps

For the full picture of what Spark Connect is, why it exists, and its constraints beyond Iceberg, see
[/pyspark/spark-connect.md](/pyspark/spark-connect.md). This is the last tutorial in the numbered
series — from here, the [pyspark/](/pyspark/index.md), [catalogs/](/catalogs/index.md),
[maintenance/](/maintenance/index.md), and [performance/](/performance/index.md) reference sections are
your ongoing lookup material for building real pipelines.

# Citations

[1] [Spark Connect Overview](https://spark.apache.org/docs/latest/spark-connect-overview.html)
[2] [Quickstart: Spark Connect (PySpark docs)](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html)
[3] [Iceberg Spark Getting Started](https://iceberg.apache.org/docs/latest/spark-getting-started/)
[4] [apache/spark branch-4.1 — sbin/start-connect-server.sh (`spark-daemon.sh submit`, `--wait`)](https://github.com/apache/spark/blob/branch-4.1/sbin/start-connect-server.sh)
