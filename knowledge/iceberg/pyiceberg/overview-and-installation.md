---
type: PyIceberg Guide
title: PyIceberg — Overview and Installation
description: What PyIceberg is, why/when to use it instead of PySpark + Java Iceberg, and how to install it with the right extras for your catalog and file-io backend.
aliases: [pyiceberg, python iceberg, pip install pyiceberg, iceberg without jvm, iceberg python library, pyiceberg extras]
tags: [pyiceberg, python, installation, overview]
timestamp: 2026-07-31T00:00:00Z
resource: https://py.iceberg.apache.org
---

# Retrieval Notes

Read this first when the user asks "what is PyIceberg", "how do I install PyIceberg",
"do I need Spark/JVM for Iceberg in Python", or "which pip extras do I need for
S3/Glue/REST". For hands-on catalog config see
[catalog-configuration.md](catalog-configuration.md). For reading/writing data see
[reading-tables.md](reading-tables.md) and [writing-and-upsert.md](writing-and-upsert.md).
For the Spark/Java side of Iceberg, see the sibling `pyspark/` concepts elsewhere in
this bundle (owned by another part of this knowledge base).

# Summary

- **PyIceberg is a pure-Python implementation of the Iceberg table format — it does
  NOT require a JVM or Spark.** This is a separate, independent codebase from the
  Java `iceberg-core`/`iceberg-spark-runtime` libraries.
- **PySpark, by contrast, uses the Java Iceberg library under the hood** (via the
  `iceberg-spark-runtime` jar) even though you write Python code — it still needs a
  JVM. PyIceberg is for lightweight, JVM-free, Python-native access.
- Use PyIceberg when you want direct Python access to Iceberg tables for
  pandas/Polars/DuckDB/Ray/Daft/PyArrow-based workflows, small-to-medium data, local
  tooling, notebooks, or embedding Iceberg reads/writes in a Python service —
  without standing up a Spark cluster.
- Still prefer Spark/PySpark for large-scale distributed compute, complex
  multi-table transactions at scale, and heavier maintenance operations (see
  Configuration differences below — compaction is not yet in PyIceberg).
- Install with `pip install "pyiceberg[...]"`, choosing extras for your catalog
  type (`glue`, `hive`, `sql-postgres`, `sql-sqlite`) and file-io backend (`s3fs`,
  `adlfs`, `gcsfs`, `pyarrow`).
- PyIceberg interoperates with pandas, Polars, DuckDB, Ray, Daft, Bodo, and Apache
  DataFusion (experimental) as query/compute engines on top of Iceberg tables.

# What is PyIceberg

PyIceberg is a Python implementation for accessing Iceberg tables, without the
need of a JVM. It is catalog-centric: reading and writing data always goes via a
catalog (REST, Glue, Hive, SQL, DynamoDB, or in-memory), never by touching files
directly (except for the read-only `StaticTable` path).

## PyIceberg vs. PySpark + Java Iceberg — do not confuse these

| | PyIceberg | PySpark + Iceberg |
|---|---|---|
| Language runtime | Pure Python | Python driving a JVM |
| Requires JVM? | No | Yes (via `iceberg-spark-runtime` jar) |
| Underlying implementation | Independent Python codebase (`pyiceberg`), with an optional Rust-accelerated core (`pyiceberg-core` / `iceberg-rust`) | Java `iceberg-core` library |
| Typical use case | Notebooks, small/medium data, embedding in Python apps, pandas/Polars/DuckDB workflows | Large-scale distributed ETL, big compute clusters |
| Compaction / rewrite_data_files | Not available (see [maintenance-with-pyiceberg.md](maintenance-with-pyiceberg.md)) | Full support via Spark procedures/actions |
| Install | `pip install pyiceberg[...]` | Spark + Iceberg runtime jar |

This distinction is easy for a learner to miss because both are "Python", but
they are architecturally very different — **PyIceberg never launches a JVM**.

# Installation

Upgrade pip first, then install with the extras you need:

```bash
pip install --upgrade pip
pip install "pyiceberg[s3fs,hive]"
```

You must install at least one of `s3fs`, `adlfs`, `gcsfs`, or `pyarrow` to be able
to fetch files from an object store.

## Available extras

| Key | Description |
|---|---|
| `hive` | Support for the Hive metastore |
| `hive-kerberos` | Support for Hive metastore in a Kerberos environment |
| `glue` | Support for AWS Glue |
| `dynamodb` | Support for AWS DynamoDB |
| `bigquery` | Support for Google Cloud BigQuery |
| `sql-postgres` | Support for SQL Catalog backed by PostgreSQL |
| `sql-sqlite` | Support for SQL Catalog backed by SQLite |
| `pyarrow` | PyArrow as a FileIO implementation to interact with the object store |
| `pandas` | Installs both PyArrow and Pandas |
| `duckdb` | Installs both PyArrow and DuckDB |
| `ray` | Installs PyArrow, Pandas, and Ray |
| `bodo` | Installs Bodo |
| `daft` | Installs Daft |
| `polars` | Installs Polars |
| `s3fs` | S3FS as a FileIO implementation to interact with the object store |
| `adlfs` | ADLFS as a FileIO implementation to interact with the object store |
| `snappy` | Support for snappy Avro compression |
| `gcsfs` | GCSFS as a FileIO implementation to interact with the object store |
| `rest-sigv4` | AWS SIGv4 authentication headers for REST Catalogs |
| `pyiceberg-core` | Installs iceberg-rust powered core |
| `datafusion` | Installs both PyArrow and Apache DataFusion |
| `hf` | Support for Hugging Face Hub |
| `gcp-auth` | Support for Google Cloud authentication |
| `entra-auth` | Support for Azure Entra (Azure AD) authentication |

# Supported compute/query engines

PyIceberg tables can be scanned and materialized into (or read directly by) several
engines — see [reading-tables.md](reading-tables.md) for scan-level detail on each:

- **PyArrow** — `to_arrow()`, `to_arrow_batch_reader()` — the base interchange format.
- **Pandas** — `to_pandas()`.
- **DuckDB** — `to_duckdb()` returns an in-memory DuckDB connection/table.
- **Ray** — `to_ray()` returns a Ray Dataset.
- **Daft** — `to_daft()` / `table.to_daft()`, a lazily-optimized query engine on top of PyIceberg tables.
- **Polars** — `to_polars()` (DataFrame) and `table.to_polars()` (LazyFrame).
- **Bodo** — `table.to_bodo()`, a drop-in Pandas replacement with HPC optimizations.
- **Apache DataFusion** — experimental, via `iceberg-rust`'s Custom Table Provider (`ctx.register_table(...)`), requires `datafusion` and `pyiceberg-core`.

# Examples

## Quickstart: local SQLite catalog + PyArrow write

```python
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

import pyarrow.parquet as pq

df = pq.read_table("/tmp/yellow_tripdata_2023-01.parquet")

catalog.create_namespace("default")

table = catalog.create_table(
    "default.taxi_dataset",
    schema=df.schema,
)

table.append(df)
len(table.scan().to_arrow())
```

The `sql` catalog (SQLite-backed) is convenient for local exploration but should
not be used in production due to limited scalability and concurrency.

# Citations

[1] [PyIceberg — Getting started](https://py.iceberg.apache.org)
