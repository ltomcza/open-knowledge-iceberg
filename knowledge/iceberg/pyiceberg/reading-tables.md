---
type: PyIceberg Guide
title: PyIceberg — Reading Tables
description: Loading tables and scanning data with PyIceberg — row/column filters, limits, conversion to pandas/Arrow/DuckDB/Ray/Daft/Polars/Bodo, and time-travel reads.
aliases: [pyiceberg scan, table.scan, pyiceberg to_pandas, pyiceberg to_arrow, pyiceberg to_duckdb, pyiceberg time travel, load_table]
tags: [pyiceberg, python, reading, scan, time-travel, pandas, arrow, duckdb]
timestamp: 2026-10-22T00:00:00Z
resource: https://py.iceberg.apache.org/api
---

# Retrieval Notes

Read this first for "how do I query/read an Iceberg table with PyIceberg",
"convert an Iceberg scan to a dataframe", or "how do I time-travel a PyIceberg
table". For filter syntax detail, see
[expressions-and-row-filters.md](expressions-and-row-filters.md). For
writes/upserts see [writing-and-upsert.md](writing-and-upsert.md). For loading a
catalog in the first place, see
[catalog-configuration.md](catalog-configuration.md).

# Summary

- Load a table via a catalog: `catalog.load_table("ns.table")` (tuple form
  `("ns", "table")` also works, useful when names contain dots).
- Or load read-only directly from a `metadata.json` path with `StaticTable` —
  no catalog needed, but write operations are unavailable.
- `table.scan(row_filter=..., selected_fields=..., limit=..., snapshot_id=...)`
  returns a lazy `DataScan`; nothing is read until you materialize it.
- `row_filter` accepts either a SQL-like string (`"trip_distance > 10.0"`) or an
  Expression DSL object (`GreaterThanOrEqual("trip_distance", 10.0)`).
- Materialize a scan with `.to_arrow()`, `.to_arrow_batch_reader()`,
  `.to_pandas()`, `.to_duckdb()`, `.to_ray()`, `.to_polars()`; or read the whole
  table lazily with `table.to_polars()` (LazyFrame) / `table.to_bodo()`.
- Time travel: pass `snapshot_id=<id>` to `table.scan(...)`, or resolve a
  timestamp to a snapshot first with
  `table.snapshot_as_of_timestamp(timestamp_ms, inclusive=True)`.
- Only files that can possibly contain matching rows are opened — PyIceberg
  prunes using Iceberg metadata (partition values, column stats) before any
  Parquet I/O happens.

# Loading a Table

```python
from pyiceberg.catalog import load_catalog

catalog = load_catalog("default")
table = catalog.load_table("docs_example.bids")
# Equivalent to:
table = catalog.load_table(("docs_example", "bids"))
```

Check existence, rename, or drop:

```python
catalog.table_exists("docs_example.bids")          # -> bool
catalog.rename_table(from_identifier="docs_example.bids", to_identifier="docs_example.bids_backup")
catalog.drop_table("docs_example.bids")             # metadata only
catalog.purge_table("docs_example.bids")            # drop + delete data/metadata files
```

## Static (catalog-free) reads

```python
from pyiceberg.table import StaticTable

static_table = StaticTable.from_metadata(
    "s3://warehouse/wh/nyc.db/taxis/metadata/00002-6ea51ce3-62aa-4197-9cf8-43d07c3440ca.metadata.json"
)

# If a version-hint.text file exists, point at the table root instead:
static_table = StaticTable.from_metadata("s3://warehouse/wh/nyc.db/taxis")
```

`StaticTable` is **read-only** — no write operations.

# Scanning

`Table.scan` signature (from the PyIceberg source):

```python
def scan(
    self,
    row_filter: str | BooleanExpression = ALWAYS_TRUE,
    selected_fields: tuple[str, ...] = ("*",),
    case_sensitive: bool = True,
    snapshot_id: int | None = None,
    options: Properties = EMPTY_DICT,
    limit: int | None = None,
) -> DataScan:
```

```python
from pyiceberg.catalog import load_catalog
from pyiceberg.expressions import GreaterThanOrEqual

catalog = load_catalog("default")
table = catalog.load_table("nyc.taxis")

scan = table.scan(
    row_filter=GreaterThanOrEqual("trip_distance", 10.0),
    selected_fields=("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"),
    limit=100,
)

# Or filter using a string predicate
scan = table.scan(row_filter="trip_distance > 10.0")

[task.file.file_path for task in scan.plan_files()]
```

`scan.plan_files()` is the low-level API: it returns the set of file tasks that
*might* contain matching rows — filtering within those files is then done by
whichever materialization method you call (`to_arrow()`, `to_duckdb()`, etc.).

# Materializing a Scan

## Apache Arrow (requires `pyarrow`)

```python
table.scan(
    row_filter=GreaterThanOrEqual("trip_distance", 10.0),
    selected_fields=("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"),
).to_arrow()
```

Stream results as `RecordBatchReader` instead of materializing everything:

```python
for buf in table.scan().to_arrow_batch_reader():
    print(f"Buffer contains {len(buf)} rows")
```

## Pandas (requires `pandas`)

```python
table.scan(
    row_filter="trip_distance >= 10.0",
    selected_fields=("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"),
).to_pandas()
```

Pandas 2+ is recommended — it stores data in an Arrow backend, avoiding copies.

## DuckDB (requires `duckdb`)

```python
con = table.scan(
    row_filter=GreaterThanOrEqual("trip_distance", 10.0),
    selected_fields=("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"),
).to_duckdb(table_name="distant_taxi_trips")

con.execute(
    "SELECT tpep_dropoff_datetime - tpep_pickup_datetime AS duration FROM distant_taxi_trips LIMIT 4"
).fetchall()
```

## Ray (requires `ray`)

```python
ray_dataset = table.scan(
    row_filter=GreaterThanOrEqual("trip_distance", 10.0),
    selected_fields=("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"),
).to_ray()

ray_dataset.take(2)
```

## Daft (requires `daft`)

```python
df = table.to_daft()  # equivalent to daft.read_iceberg(table)
df = df.where(df["trip_distance"] >= 10.0)
df = df.select("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime")
df.show(2)   # lazily optimized; triggers execution
```

## Polars (requires `polars`)

```python
# DataFrame (via a scan)
table.scan(row_filter="ticket_id > 10").to_polars()

# LazyFrame (direct table access, for Polars-native filtering)
lf = table.to_polars().filter(pl.col("ticket_id") > 10)
lf.collect()
```

Use `table.scan().to_polars()` when the Iceberg scan/filter API drives retrieval;
use `table.to_polars()` (LazyFrame) when Polars' own optimizer should drive
filtering/pushdown.

## Bodo (requires `bodo`, `pip install pyiceberg['bodo']`)

```python
df = table.to_bodo()  # equivalent to bodo.pandas.read_iceberg_table(table)
df = df[df["trip_distance"] >= 10.0]
df = df[["VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime"]]
print(df)   # print triggers lazy execution
```

## Apache DataFusion (experimental, requires `datafusion` + `pyiceberg-core`)

```python
from datafusion import SessionContext
from pyiceberg.catalog import load_catalog
import pyarrow as pa

catalog = load_catalog("catalog", type="in-memory")
catalog.create_namespace_if_not_exists("default")

data = pa.table({"x": [1, 2, 3], "y": [4, 5, 6]})
iceberg_table = catalog.create_table("default.test", schema=data.schema)
iceberg_table.append(data)

ctx = SessionContext()
ctx.register_table("test", iceberg_table)
ctx.table("test").show()
```

Caveats: works only with `datafusion == 53` (PyIceberg 0.12 docs; the pin moves with `pyiceberg-core`) (matching `pyiceberg-core`), depends
directly on `iceberg-rust` rather than PyIceberg's own implementation, and has
fewer features than the full PyIceberg API.

# Time Travel

Pass a specific `snapshot_id` to `scan()`:

```python
table.scan(snapshot_id=805611270568163028).to_arrow()
```

Resolve a timestamp to the applicable snapshot first, then scan it:

```python
snapshot = table.snapshot_as_of_timestamp(timestamp_ms, inclusive=True)
table.scan(snapshot_id=snapshot.snapshot_id).to_arrow()
```

Metadata-table inspection also supports a `snapshot_id` argument (all
`table.inspect.*` methods except `snapshots()` and `refs()`):

```python
table.inspect.entries(snapshot_id=805611270568163028)
```

For the underlying snapshot/branch/tag concepts, see
[/architecture/snapshots-and-versioning.md](/architecture/snapshots-and-versioning.md) and
[/maintenance/expire-snapshots.md](/maintenance/expire-snapshots.md).

# Inspecting Table Metadata

`table.inspect.<method>()` returns a PyArrow table of internal metadata:

| Method | Returns |
|---|---|
| `table.inspect.snapshots()` | All snapshots (id, parent, operation, summary) |
| `table.inspect.partitions()` | Per-partition file/record counts and sizes |
| `table.inspect.entries()` | Manifest entries for current data + delete files, incl. `readable_metrics` |
| `table.inspect.refs()` | Branches and tags with retention settings |
| `table.inspect.manifests()` | Current manifest files |
| `table.inspect.metadata_log_entries()` | Metadata JSON file history |
| `table.inspect.history()` | Snapshot history with ancestor lineage |
| `table.inspect.files()` | All data files in the current snapshot |
| `table.inspect.data_files()` / `.delete_files()` | Data-only or delete-only file subset |

`content` in file-level results: `0` = Data, `1` = Position Deletes, `2` =
Equality Deletes.

# Citations

[1] [PyIceberg — Python API](https://py.iceberg.apache.org/api)
