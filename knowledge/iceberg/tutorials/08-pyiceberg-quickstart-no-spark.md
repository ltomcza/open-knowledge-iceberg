---
type: Tutorial
title: 8. PyIceberg Quickstart (No Spark)
description: Create, write, and read an Iceberg table using pure Python PyIceberg and a local SQLite catalog -- no JVM or SparkSession involved.
aliases: [pyiceberg tutorial, pyiceberg quickstart, iceberg without spark, pyiceberg sql catalog sqlite]
tags: [tutorial, pyiceberg, python, no-spark, beginner]
timestamp: 2026-10-22T00:00:00Z
difficulty: beginner
---

# Prerequisites

- Python 3.10+ and pip (PyIceberg 0.12 requires Python >= 3.10). **No Java, no Spark, no JVM required for this tutorial** — that's the point.
- Conceptually helpful (but not required) to have done
  [2. Your First Table: Create, Insert, Read](/tutorials/02-first-table-crud.md) first, since this
  tutorial repeats the same "create table, write, read" journey using a completely different tool.

# What You'll Learn

- How PyIceberg differs from the tutorials 1-7: it talks to Iceberg tables directly from Python,
  using Apache Arrow for data and no JVM at all.
- How to configure a local, dependency-free catalog (`SqlCatalog` backed by SQLite) — PyIceberg's
  equivalent of the local Hadoop catalog used throughout this series.
- How to create a table from a PyArrow schema, append data, and read it back as pandas/Arrow.
- When you'd reach for PyIceberg instead of PySpark.

# Steps

## 1. Install PyIceberg

```bash
pip install --upgrade pip
pip install "pyiceberg[pyarrow,pandas,sql-sqlite]"
```

**Expected output:** pip installs `pyiceberg` along with PyArrow (for reading/writing data and for
the local `file://` FileIO), pandas (for `.to_pandas()`), and SQLite catalog support. No `s3fs`,
`hive`, or any other network-catalog extras are needed for this local-only tutorial.

## 2. Create a warehouse directory and load a local catalog

```python
import os

warehouse_path = "/tmp/warehouse_pyiceberg"
os.makedirs(warehouse_path, exist_ok=True)

from pyiceberg.catalog import load_catalog

catalog = load_catalog(
    "default",
    **{
        "type": "sql",
        "uri": f"sqlite:///{warehouse_path}/pyiceberg_catalog.db",
        "warehouse": f"file://{warehouse_path}",
    },
)

print(catalog)
```

**Expected output:** a `<SqlCatalog ...>` repr, and a new `pyiceberg_catalog.db` SQLite file created
under `/tmp/warehouse_pyiceberg`. This `SqlCatalog` is for local development and testing only — it's
not built for concurrent access, which is why it's a good fit for a single-process tutorial.

## 3. Create a namespace and a table from a PyArrow schema

```python
import pyarrow as pa

catalog.create_namespace("default")

schema = pa.schema([
    pa.field("city", pa.string(), nullable=False),
    pa.field("lat", pa.float64(), nullable=False),
    pa.field("long", pa.float64(), nullable=False),
])

table = catalog.create_table(
    identifier="default.cities",
    schema=schema,
)

print(table.schema())
```

**Expected output:** the table's Iceberg schema printed back, with re-assigned field IDs, e.g.:

```
table {
  1: city: required string
  2: lat: required double
  3: long: required double
}
```

## 4. Append data with a PyArrow table

```python
data = pa.Table.from_pylist(
    [
        {"city": "Amsterdam", "lat": 52.371807, "long": 4.896029},
        {"city": "San Francisco", "lat": 37.773972, "long": -122.431297},
        {"city": "Drachten", "lat": 53.11254, "long": 6.0989},
        {"city": "Paris", "lat": 48.864716, "long": 2.349014},
    ],
    schema=schema,
)

table.append(data)
```

**Expected output:** no errors. This wrote a new Parquet data file under
`/tmp/warehouse_pyiceberg/default/cities/data/` (the SQL catalog uses `<warehouse>/<namespace>/<table>`; only the Glue, Hive, and DynamoDB catalogs add a Hive-style `.db` suffix) and committed a new snapshot — the same kind of
snapshot you inspected via Spark's `.snapshots` metadata table in earlier tutorials, just written by
a pure-Python client this time.

## 5. Read the table back

```python
df = table.scan().to_pandas()
print(df)
```

**Expected output:**

```
            city        lat        long
0      Amsterdam  52.371807    4.896029
1  San Francisco  37.773972 -122.431297
2       Drachten  53.112540    6.098900
3          Paris  48.864716    2.349014
```

You can also get an Arrow table directly, or apply a row filter pushed down to file statistics:

```python
arrow_table = table.scan().to_arrow()
print(arrow_table.num_rows)

paris_only = table.scan(row_filter="city == 'Paris'").to_pandas()
print(paris_only)
```

**Expected output:** `4` for the row count, and a one-row DataFrame containing only `Paris` for the
filtered scan.

## 6. Inspect table metadata, PyIceberg-style

The same kind of introspection you did with Spark's `.snapshots` / `.files` SQL metadata tables is
available through the `table.inspect` API:

```python
print(table.inspect.snapshots().to_pandas()[["snapshot_id", "operation"]])
print(table.inspect.files().to_pandas()[["file_path", "record_count"]])
```

**Expected output:** one snapshot row with `operation = 'append'`, and one or more file rows
matching the data you just wrote.

# How This Differs From Tutorials 1-7

- **No JVM, no SparkSession.** Everything here runs in a single Python process. There's no
  `--packages` jar resolution step and no Spark startup banner.
- **Apache Arrow instead of Spark DataFrames.** Data moves in and out of tables as PyArrow Tables
  (or pandas, via `.to_pandas()`), not Spark DataFrames.
- **A `SqlCatalog`, not a Hadoop catalog.** PyIceberg's local-dev catalog uses a small SQLite
  database to track table locations; Spark's Hadoop catalog instead infers table identity from
  directory structure. Both are meant for local development, not production.
- **When to reach for this instead:** lightweight scripts, notebooks, and services that need to
  read or write Iceberg tables without paying the cost of starting a Spark cluster — for example, a
  small ETL script, a FastAPI service, or a Jupyter notebook doing exploratory analysis. For
  large-scale distributed transformations, joins across huge tables, or streaming, reach for Spark
  (tutorials 1-7) instead.

# Common Pitfalls

- **Forgetting the `pyarrow` extra.** PyIceberg needs a FileIO implementation to talk to `file://`
  paths; without `pyarrow` (or `s3fs`/`adlfs`/`gcsfs` for cloud storage), table creation and scans
  will fail with an error about no FileIO being available for the scheme.
- **Using `SqlCatalog`/SQLite in a multi-process or production setting.** It's explicitly for local
  development — SQLite doesn't handle concurrent writers safely. Use a REST, Hive, Glue, or JDBC
  (Postgres-backed) catalog for anything shared or production-facing.
- **Expecting `.append()` to compact automatically.** Each `.append()` writes new data files and a new
  snapshot, so repeated small appends accumulate small files here just as in Spark — and PyIceberg has
  no compaction, so use Spark's `rewrite_data_files` (the same lesson as
  [6. Compaction and Maintenance](/tutorials/06-compaction-and-maintenance.md)). Unlike Java/Spark,
  PyIceberg also defaults to *fast* append (`commit.manifest-merge.enabled=False`), so manifests pile up
  too.
- **Mixing up `table.append()` and `table.overwrite()`.** On an empty table they produce the same
  result, but `overwrite()` replaces existing data matching an optional filter — it is not simply
  "insert more rows."

# Next Steps

Continue to [9. Iceberg Through Spark Connect](/tutorials/09-spark-connect.md) for the last tutorial in the series. For deeper PyIceberg material — the full catalog matrix,
schema/partition evolution, upsert, and REST/Glue/Hive catalog configuration — see
[/pyiceberg/overview-and-installation.md](/pyiceberg/overview-and-installation.md).

If you skipped straight here, consider working through
[1. Environment Setup](/tutorials/01-environment-setup.md) through
[7. Structured Streaming into Iceberg](/tutorials/07-structured-streaming-into-iceberg.md) for the
Spark-based side of the ecosystem, which covers distributed writes, `MERGE INTO`, and streaming that
PyIceberg alone doesn't provide.

# Citations

[1] [Getting Started with PyIceberg](https://py.iceberg.apache.org/)
[2] [PyIceberg Python API — Create, write, upsert, and inspect tables](https://py.iceberg.apache.org/api/)
[3] [PyIceberg Configuration — Catalogs (SQL, REST, Hive, Glue, DynamoDB)](https://py.iceberg.apache.org/configuration/)
[4] [PyPI — pyiceberg 0.12.0 (requires Python >= 3.10)](https://pypi.org/project/pyiceberg/)
