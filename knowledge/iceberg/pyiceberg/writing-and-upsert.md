---
type: PyIceberg Guide
title: PyIceberg — Writing, Deleting, and Upserting Data
description: Appending, overwriting, deleting, and upserting Arrow data into Iceberg tables with PyIceberg, plus transactions and snapshot properties.
aliases: [pyiceberg append, pyiceberg overwrite, pyiceberg upsert, pyiceberg delete, pyiceberg transaction, table.append, table.upsert, dynamic_partition_overwrite]
tags: [pyiceberg, python, writing, upsert, delete, transaction]
timestamp: 2026-10-22T00:00:00Z
resource: https://py.iceberg.apache.org/api
---

# Retrieval Notes

Read this first for "how do I write/append/upsert/delete data with PyIceberg" or
"how do transactions work in PyIceberg". For reading data back, see
[reading-tables.md](reading-tables.md). For schema/partition changes (also done
via transactions), see
[schema-and-partition-evolution.md](schema-and-partition-evolution.md). For
filter syntax used in `delete_filter`/`overwrite_filter`, see
[expressions-and-row-filters.md](expressions-and-row-filters.md).

# Summary

- Writes are done with PyArrow tables: `table.append(df)`,
  `table.overwrite(df, overwrite_filter=...)`, `table.delete(delete_filter=...)`,
  `table.upsert(df, join_cols=[...])`, and `table.dynamic_partition_overwrite(df)`.
  `append()`/`overwrite()` also accept a `pyarrow.RecordBatchReader` to stream
  larger-than-memory data into files of about `write.target-file-size-bytes`
  (unpartitioned tables only, current docs).
- **PyIceberg defaults to "fast append"** (unlike Java Iceberg's merge-on-commit
  default) — this speeds up commits and reduces conflicts but creates more
  metadata over time. **Compaction is not yet built into PyIceberg** (tracked
  upstream) — see [maintenance-with-pyiceberg.md](maintenance-with-pyiceberg.md).
- `table.delete(delete_filter=...)` drops whole Parquet files without reading them
  when Iceberg metadata proves every row in the file matches the filter.
- `table.upsert(df, join_cols=...)` matches rows on `join_cols` (or the table's
  configured identifier fields if omitted): matched rows are updated, new rows are
  inserted; returns an `UpsertResult` with `.rows_updated` / `.rows_inserted`.
- Any multi-step change (schema + spec + properties, etc.) should go through
  `with table.transaction() as txn:` so it commits atomically as one operation.
- `add_files(file_paths=[...])` commits **existing** Parquet files as data files
  without rewriting them — useful for migrating external Parquet into Iceberg.

# Append and Overwrite

```python
import pyarrow as pa
from pyiceberg.catalog import load_catalog

catalog = load_catalog("default")

df = pa.Table.from_pylist([
    {"city": "Amsterdam", "lat": 52.371807, "long": 4.896029},
    {"city": "San Francisco", "lat": 37.773972, "long": -122.431297},
])

tbl = catalog.create_table("default.cities", schema=df.schema)

# On an empty table, append and overwrite produce the same result:
tbl.append(df)
# or
tbl.overwrite(df)
```

> **Fast append**: PyIceberg defaults to fast append to minimize the amount of
> data written and speed up commits. The tradeoff is more metadata files than a
> merge commit produces; PyIceberg does not yet auto-compact this metadata.

Avoid type mismatches by writing with the table's own Arrow schema:

```python
df = pa.Table.from_pylist(
    [{"city": "Groningen", "lat": 53.21917, "long": 6.56667}],
    schema=table.schema().as_arrow(),
)
tbl.append(df)
```

## Partial overwrite with a filter

`overwrite_filter` deletes matching rows before appending the new data:

```python
from pyiceberg.expressions import EqualTo

df = pa.Table.from_pylist([{"city": "New York", "lat": 40.7128, "long": 74.0060}])
tbl.overwrite(df, overwrite_filter=EqualTo('city', "Paris"))
```

## Dynamic partition overwrite

For partitioned tables, `dynamic_partition_overwrite(df)` replaces only the
partitions present in `df`, auto-detected from the data — no filter needed:

```python
df_corrected = pa.Table.from_pylist([{"city": "Paris", "lat": 48.864716, "long": 2.349014}])
tbl.dynamic_partition_overwrite(df_corrected)
```

# Delete

```python
def delete(
    self,
    delete_filter: str | BooleanExpression,
    snapshot_properties: dict[str, str] = EMPTY_DICT,
    case_sensitive: bool = True,
    branch: str | None = MAIN_BRANCH,
) -> None:
```

```python
tbl.delete(delete_filter="city == 'Paris'")
```

If Iceberg metadata proves an entire Parquet file's contents match the filter
(e.g. `delete_filter="city == 'Groningen'"` where that file only holds
`Groningen` rows), the whole file is dropped without being opened or scanned.

# Upsert

```python
def upsert(
    self,
    df: pa.Table,
    join_cols: list[str] | None = None,
    when_matched_update_all: bool = True,
    when_not_matched_insert_all: bool = True,
    case_sensitive: bool = True,
    branch: str | None = MAIN_BRANCH,
    snapshot_properties: dict[str, str] = EMPTY_DICT,
) -> UpsertResult:
```

Rows are matched by `join_cols` (or the table's `identifier_field_ids` if
`join_cols` is omitted). Matched rows are updated; unmatched rows are inserted.

```python
from pyiceberg.schema import Schema
from pyiceberg.types import IntegerType, NestedField, StringType
import pyarrow as pa

schema = Schema(
    NestedField(1, "city", StringType(), required=True),
    NestedField(2, "inhabitants", IntegerType(), required=True),
    identifier_field_ids=[1],  # "city" is the primary key
)
tbl = catalog.create_table("default.cities", schema=schema)

arrow_schema = pa.schema([
    pa.field("city", pa.string(), nullable=False),
    pa.field("inhabitants", pa.int32(), nullable=False),
])
tbl.append(pa.Table.from_pylist(
    [
        {"city": "Amsterdam", "inhabitants": 921402},
        {"city": "Drachten", "inhabitants": 45019},
        {"city": "Paris", "inhabitants": 2103000},
    ],
    schema=arrow_schema,
))

df = pa.Table.from_pylist(
    [
        {"city": "Drachten", "inhabitants": 45505},   # updated
        {"city": "Berlin", "inhabitants": 3432000},    # inserted
        {"city": "Paris", "inhabitants": 2103000},     # unchanged, ignored
    ],
    schema=arrow_schema,
)
upd = tbl.upsert(df)

assert upd.rows_updated == 1
assert upd.rows_inserted == 1
```

# Snapshot Properties on Writes

```python
tbl.append(df, snapshot_properties={"abc": "def"})
# or
tbl.overwrite(df, snapshot_properties={"abc": "def"})

assert tbl.metadata.snapshots[-1].summary["abc"] == "def"
```

# Transactions

Wrap multiple operations so they commit as a single atomic change:

```python
with table.transaction() as transaction:
    with transaction.update_schema() as update_schema:
        update_schema.add_column("some_other_field", IntegerType(), "doc")
    # ... update properties, spec, sort order, etc.
```

Table properties, without a context manager:

```python
table = table.transaction().set_properties(abc="def").commit_transaction()
assert table.properties == {"abc": "def"}

table = table.transaction().remove_properties("abc").commit_transaction()
assert table.properties == {}
```

`create_table_transaction` lets you set schema, partition spec, sort order, and
properties atomically at table-creation time, using the friendly (non
field-ID-aware) update APIs:

```python
with catalog.create_table_transaction(identifier="docs_example.bids", schema=schema) as txn:
    with txn.update_schema() as update_schema:
        update_schema.add_column(path="new_column", field_type='string')

    with txn.update_spec() as update_spec:
        update_spec.add_identity("symbol")

    txn.set_properties(test_a="test_aa", test_b="test_b", test_c="test_c")
```

# Adding Existing Parquet Files (`add_files`)

Commit pre-existing Parquet files as data files **without rewriting them**:

```python
file_paths = [
    "s3a://warehouse/default/existing-1.parquet",
    "s3a://warehouse/default/existing-2.parquet",
]
tbl.add_files(file_paths=file_paths)
# A new snapshot is committed with manifests pointing at the existing files
```

| Parameter | Required | Type | Description |
|---|---|---|---|
| `file_paths` | Yes | `List[str]` | Files to add as data files |
| `snapshot_properties` | No | `Dict[str, str]` | Properties on the new snapshot (default `{}`) |
| `check_duplicate_files` | No | `bool` | Validate no path is already a table data file (default `True`) |

Notes:

- Works with files that have Iceberg field IDs embedded (e.g. written by Spark)
  **or** without them — in the latter case PyIceberg auto-creates a Name Mapping
  from the current table schema if one doesn't exist.
- Supports partition transforms that preserve value order (e.g. `MonthTransform`,
  `TruncateTransform`); partition values are inferred from the Parquet footer
  statistics, or `None` if those stats are missing.
- Because these files become ordinary data files, destructive maintenance (e.g.
  expiring snapshots) can later remove them just like any other file.
- Leave `check_duplicate_files=True` (default) unless you have another mechanism
  guaranteeing no duplicate paths — disabling it trades a consistency check for
  performance on tables with many files.

# Citations

[1] [PyIceberg — Python API](https://py.iceberg.apache.org/api)
[2] [PyIceberg — Streaming writes from a RecordBatchReader](https://py.iceberg.apache.org/api/#streaming-writes-from-a-recordbatchreader)
