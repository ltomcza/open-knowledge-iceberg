---
type: Iceberg Concept
title: Schema Evolution
description: How Iceberg supports safe, in-place schema changes (add/drop/rename/reorder/widen columns) via permanent column IDs, and why this differs from Hive/Parquet schema evolution.
aliases: [schema evolution, add column, drop column, rename column, column id, type promotion, iceberg vs hive schema, correctness guarantees]
tags: [iceberg, architecture, schema, evolution, correctness]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/evolution
---

# Retrieval Notes

Read this for how and why Iceberg schema changes are safe and metadata-only.
For the type system itself, see the "Types" section below and the spec. For
partition spec changes (a related but distinct evolution mechanism), see
[partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md).
For where schemas live in table metadata, see [metadata-layer.md](metadata-layer.md).

# Summary

- Iceberg supports **in-place schema evolution**: add, drop, rename, update
  (widen type), and reorder columns — including inside nested structs — as
  pure **metadata changes**. No data files are rewritten.
- Evolution is **guaranteed free of side effects**: adding a column never
  reads stale values from another column; dropping a column never changes
  other columns' values; reordering never changes which values belong to
  which field.
- This correctness guarantee is possible because every field (top-level or
  nested) has a permanent, unique **column ID** that is assigned once and
  **never reused**, even after the field is dropped.
- Columns in data files are resolved by **field ID**, not by name or
  position — so renames and reorders are metadata-only and never touch
  data files.
- Each schema change produces a **new schema object** with a new schema ID,
  appended to the table's `schemas` list, and set as `current-schema-id` —
  old schemas remain in metadata (used e.g. for reading old snapshots or
  querying tags — see [branching-and-tagging.md](branching-and-tagging.md)).
- Only a restricted set of **type promotions** are valid (e.g. `int` →
  `long`, `float` → `double`, widening `decimal` precision) — no arbitrary
  type changes.

# Supported Changes

| Change | Effect |
|---|---|
| **Add** | Add a new column to the table or a nested struct. Gets a brand-new column ID. |
| **Drop** | Remove an existing column or field. Its ID is retired, never reused. |
| **Rename** | Change a column/field's name. The field ID is unchanged. |
| **Update** | Widen the type of a column, struct field, map key, map value, or list element (see valid promotions below). |
| **Reorder** | Change the order of columns/fields in a struct. |

Map keys specifically do **not** support adding/dropping struct fields that
would change key equality semantics.

# Why It's Safe — Column IDs

- Every field gets an integer ID, unique within the table schema, assigned
  when the field is first added and tracked in `last-column-id` at the
  table-metadata level so new fields never collide with old (even dropped)
  ones.
- **Column projection** at read time resolves file columns using field IDs,
  not names/positions. If a data file lacks a field id, the spec resolves
  it in this order: (1) the identity-partition value from the manifest's
  `partition` struct, (2) `schema.name-mapping.default` for files written
  without field ids, (3) the field's `initial-default`, (4) `null`.
  (Corrected 2026-10-22 — an earlier version had the order wrong and
  omitted the identity-partition step.)
- Consequence: formats that track columns **by name** can accidentally
  "un-delete" data if a name is reused for a different field — this
  violates Iceberg's guarantee #1 (added columns never inherit stale
  values) and Iceberg avoids it entirely because a new field always gets a
  fresh ID even if it reuses an old name.
- Formats that track columns **by position** cannot delete a column without
  shifting every subsequent column's effective identity — Iceberg avoids
  this because identity is by ID, not position.

# Why This Differs from Hive / Parquet Evolution

| | Hive / plain Parquet | Iceberg |
|---|---|---|
| Column identity | Name or ordinal position | Permanent field ID |
| Rename | Often unsupported, or a metadata rename that can silently break downstream readers keyed on name | Metadata-only; ID unchanged, so no silent breakage |
| Reorder | Can shift positional readers' interpretation of columns | No effect on any column's data — reads are ID-based |
| Drop + re-add with same name | Can "resurrect" old data under the new column (name collision) | Impossible — the new column gets a new ID; old data is never associated with it |
| Rewrite required? | Frequently yes for structural changes | Never for add/drop/rename/reorder/widen |

# Type Promotion Rules

Only widening promotions are valid (v1/v2; v3 adds a couple more):

| From | To (v1/v2) | To (v3+) |
|---|---|---|
| `int` | `long` | `long` |
| `float` | `double` | `double` |
| `decimal(P,S)` | `decimal(P',S)` where `P' > P` (scale fixed) | same |
| `date` | — | `timestamp`, `timestamp_ns` (not `timestamptz*`) |
| `unknown` | — | any type |

Type promotion does not rewrite existing file-level min/max bounds; readers
must infer the original on-disk type from the byte-length of the stored
bound (e.g., a 4-byte bound under a `long` column means it was written as
`int`).

# Field Deletion Rollback Rule

Deleting a field can be rolled back (undone) only if the field was
**nullable**, or if the current snapshot has not changed since the delete —
otherwise old snapshots referencing the dropped field's data cannot be
safely reconciled with the newer schema.

# Not Allowed

- Grouping a subset of a struct's fields into a nested struct, or the
  reverse (`struct<a,b,c>` ↔ `struct<a, struct<b,c>>`).
- Promoting a primitive to a struct, or collapsing a single-field struct to
  a primitive.

# Example

```sql
-- Spark SQL: safe, metadata-only changes
ALTER TABLE db.table ADD COLUMN new_col date;
ALTER TABLE db.table DROP COLUMN col;
ALTER TABLE db.table RENAME COLUMN old_name TO new_name;
ALTER TABLE db.table ALTER COLUMN amount TYPE double;  -- float -> double widen
```

# Types Reference

Primitive types: `boolean`, `int`, `long`, `float`, `double`,
`decimal(P,S)`, `date`, `time`, `timestamp`, `timestamptz`, `timestamp_ns`
(v3), `timestamptz_ns` (v3), `string`, `uuid`, `fixed(L)`, `binary`,
`variant` (v3), `geometry(C)` (v3), `geography(C,A)` (v3), `unknown` (v3).
Nested types: `struct<...>`, `list<E>`, `map<K,V>`. Every field in a nested
type also has its own permanent field ID.

# Citations

[1] [Apache Iceberg Documentation — Evolution](https://iceberg.apache.org/docs/latest/evolution)
[2] [Apache Iceberg Documentation — Schemas](https://iceberg.apache.org/docs/latest/schemas)
[3] [Apache Iceberg Table Spec — Schema Evolution](https://iceberg.apache.org/spec)
