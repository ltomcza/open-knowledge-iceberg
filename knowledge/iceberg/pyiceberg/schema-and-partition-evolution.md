---
type: PyIceberg Guide
title: PyIceberg — Schema and Partition Evolution
description: Evolving table schema (add/rename/move/update/delete columns, union-by-name) and partition spec (add/remove/rename fields) and sort order through the PyIceberg transaction API.
aliases: [pyiceberg update_schema, pyiceberg update_spec, pyiceberg add_column, pyiceberg union_by_name, pyiceberg partition evolution, pyiceberg rename_column, update_sort_order]
tags: [pyiceberg, python, schema-evolution, partition-evolution, transaction]
timestamp: 2026-07-31T00:00:00Z
resource: https://py.iceberg.apache.org/api
---

# Retrieval Notes

Read this first for "how do I add/rename/delete a column in PyIceberg", "how do I
change partitioning with PyIceberg", or "union_by_name". These are all done via
short-lived transaction builders on the `Table`. For general transactions and
writes, see [writing-and-upsert.md](writing-and-upsert.md). For the underlying
Iceberg concept of safe/unsafe schema changes, see
`/architecture/schema-evolution.md`.

# Summary

- Schema changes go through `with table.update_schema() as update: ...` — PyIceberg
  assigns field IDs for you, and by default only allows non-breaking changes.
- `update.union_by_name(other_schema)` merges another schema in, matching by
  field name rather than ID — the easiest way to add several new columns at once.
- Breaking changes (e.g. deleting a column, making an optional field required)
  require `table.update_schema(allow_incompatible_changes=True)`.
- Partition spec changes go through `with table.update_spec() as update: ...`,
  using `add_field`, `remove_field`, `rename_field`, or the `identity(...)`
  shortcut.
- Sort orders are append-only: `table.update_sort_order()` can only **add** a new
  order via `.asc(...)` / `.desc(...)` — existing orders cannot be deleted or
  modified.
- Any of these builders can be nested inside `with table.transaction() as txn:`
  to combine schema, spec, sort-order, and property changes into one atomic
  commit.

# Schema Evolution

```python
with table.update_schema() as update:
    update.add_column("some_field", IntegerType(), "doc")
```

Inside a transaction (to bundle with other changes):

```python
with table.transaction() as transaction:
    with transaction.update_schema() as update_schema:
        update_schema.add_column("some_other_field", IntegerType(), "doc")
    # ... update properties etc
```

## Union by Name

Merge another `Schema` in by matching field names — no manual field-ID
bookkeeping required:

```python
from pyiceberg.catalog import load_catalog
from pyiceberg.schema import Schema
from pyiceberg.types import NestedField, StringType, DoubleType, LongType

catalog = load_catalog()

schema = Schema(
    NestedField(1, "city", StringType(), required=False),
    NestedField(2, "lat", DoubleType(), required=False),
    NestedField(3, "long", DoubleType(), required=False),
)
table = catalog.create_table("default.locations", schema)

new_schema = Schema(
    NestedField(1, "city", StringType(), required=False),
    NestedField(2, "lat", DoubleType(), required=False),
    NestedField(3, "long", DoubleType(), required=False),
    NestedField(10, "population", LongType(), required=False),
)

with table.update_schema() as update:
    update.union_by_name(new_schema)
```

## Add Column

```python
with table.update_schema() as update:
    update.add_column("retries", IntegerType(), "Number of retries to place the bid")
    # In a struct — the struct must already exist:
    update.add_column("details", StructType())

with table.update_schema() as update:
    update.add_column(("details", "confirmed_by"), StringType(), "Name of the exchange")
```

A complex type (struct) must exist before columns can be added inside it —
nested field paths are expressed as tuples.

## Rename Column

```python
with table.update_schema() as update:
    update.rename_column("retries", "num_retries")
    # Rename `confirmed_by` to `processed_by` inside the `details` struct
    update.rename_column(("details", "confirmed_by"), "processed_by")
```

## Move Column

```python
with table.update_schema() as update:
    update.move_first("symbol")
    update.move_after("bid", "ask")
    update.move_before(("details", "confirmed_by"), ("details", "exchange"))
```

## Update Column (type / required / doc)

```python
with table.update_schema() as update:
    update.update_column("bid", field_type=DoubleType())      # promote float -> double
    update.update_column("symbol", required=False)             # make optional
    update.update_column("symbol", doc="Name of the share on the exchange")
```

Breaking change, requires opt-in:

```python
with table.update_schema(allow_incompatible_changes=True) as update:
    update.update_column("symbol", required=True)   # incompatible: optional -> required
```

## Delete Column

Always an incompatible change (existing readers/writers may expect the field):

```python
with table.update_schema(allow_incompatible_changes=True) as update:
    update.delete_column("some_field")
    update.delete_column(("details", "confirmed_by"))
```

# Partition Evolution

Use `table.update_spec()`:

```python
with table.update_spec() as update:
    update.add_field("id", BucketTransform(16), "bucketed_id")
    update.add_field("event_ts", DayTransform(), "day_ts")
```

Inside a transaction with other changes:

```python
with table.transaction() as transaction:
    with transaction.update_spec() as update_spec:
        update_spec.add_field("id", BucketTransform(16), "bucketed_id")
        update_spec.add_field("event_ts", DayTransform(), "day_ts")
    # ... update properties etc
```

## Add Fields

```python
with table.update_spec() as update:
    update.add_field("id", BucketTransform(16), "bucketed_id")
    update.add_field("event_ts", DayTransform(), "day_ts")
    update.identity("some_field")   # shortcut for an IdentityTransform field
```

If a partition name isn't given, one is generated automatically.

## Remove Fields

```python
with table.update_spec() as update:
    update.remove_field("some_partition_name")
```

## Rename Fields

```python
with table.update_spec() as update:
    update.rename_field("bucketed_id", "sharded_id")
```

# Sort Order Updates

Sort orders are **append-only** — a new order can be added, but existing orders
cannot be deleted or modified:

```python
with table.update_sort_order() as update:
    update.desc("event_ts", DayTransform(), NullOrder.NULLS_FIRST)
    update.asc("some_field", IdentityTransform(), NullOrder.NULLS_LAST)
```

`asc`/`desc` both take the field name, a sort transform, and a null-ordering
constant describing where nulls sort.

# Citations

[1] [PyIceberg — Python API](https://py.iceberg.apache.org/api)
