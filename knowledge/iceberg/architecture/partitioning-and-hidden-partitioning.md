---
type: Iceberg Concept
title: Partitioning and Hidden Partitioning
description: Iceberg's hidden partitioning model, partition spec structure, and how partition layouts can evolve without rewriting existing data.
aliases: [hidden partitioning, partition spec, partition evolution, iceberg vs hive partitioning, split planning]
tags: [iceberg, architecture, partitioning, hidden-partitioning, evolution]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/partitioning
---

# Retrieval Notes

Read this for the *concept* of hidden partitioning and partition evolution.
For the full list of transform functions and their exact semantics, see
[partition-transforms-reference.md](partition-transforms-reference.md). For
how partition data is stored/pruned in manifests, see
[manifests-and-manifest-lists.md](manifests-and-manifest-lists.md). For
schema (not partition) evolution, see [schema-evolution.md](schema-evolution.md).

# Summary

- Partitioning groups rows with similar values into the same files so
  queries can skip irrelevant files. Iceberg computes partition values
  itself from a **transform of a source column** (e.g. `day(event_time)`)
  rather than requiring an explicit partition column — this is **hidden
  partitioning**.
- Because Iceberg derives partition values automatically and tracks the
  relationship in the **partition spec**, users write ordinary filters on
  data columns (`event_time BETWEEN ...`) and Iceberg translates them into
  partition predicates itself — no separate partition filter needed.
- This eliminates the classic Hive failure mode: silently wrong or slow
  results from a missing/incorrect partition filter, or from a
  producer/consumer mismatch on partition format.
- A **partition spec** is a list of fields, each with: source column
  id(s), a partition field id, a transform, and a partition name. Multiple
  specs can coexist in one table (`partition-specs` in metadata).
- **Partition evolution** — adding, removing, renaming, or reordering
  partition fields — is a **metadata-only** operation. Existing data
  written under the old spec is untouched; new data is written under the
  new spec. Both layouts coexist and are queried together via **split
  planning**.
- Because reads don't reference partition values directly, partition
  evolution never breaks existing queries.

# Iceberg vs. Hive Partitioning

| | Hive | Iceberg |
|---|---|---|
| Partition column | Explicit, physical column (e.g. `event_date`), must be supplied by the writer | Hidden — derived automatically via a transform, no separate physical column |
| Validation | None — wrong format/value/timezone silently produces wrong results | Iceberg computes and validates the value itself |
| Query requirement | Must filter on both the logical column *and* the partition column | Filter only the logical column; partition pruning is automatic |
| Changing partitioning | Requires a new table + rewriting queries | `ALTER TABLE ... ADD/DROP PARTITION FIELD`; queries unchanged |
| Partition value storage | String-encoded in file system paths/keys | Stored unmodified (typed) in manifest partition tuples |

Example of the Hive failure mode Iceberg avoids: using `2018-12-01` instead
of `20181201`, or partitioning by `processing_time` instead of the intended
`event_time` — Hive can't detect either; it just returns wrong results
without error. Iceberg's spec-driven derivation removes the possibility
because there is no user-supplied partition value to get wrong.

# Partition Spec Structure

A partition spec field has:

| Component | Description |
|---|---|
| Source column id(s) | Column(s) from the table schema the transform reads. |
| Partition field id | Unique id for the field (unique across all specs in v2+). |
| Transform | Function applied to source column(s) — see [partition-transforms-reference.md](partition-transforms-reference.md). |
| Partition name | Display name for the derived partition value. |

Source columns must be a primitive type, and cannot be nested inside a
`map` or `list` (nesting inside a `struct` is fine).

Two partition specs are equivalent if they have the same number of fields
with matching source column IDs, transform, and name — writers must not
create a redundant new spec, and must reuse partition field IDs when an
equivalent field already exists.

# Partition Evolution Mechanics

- Changing a spec creates a new spec with a new unique id, appended to
  `partition-specs`, and optionally set as `default-spec-id`.
- Partition field IDs are preserved across evolution — they double as the
  field IDs used inside manifest partition tuples, so they must stay
  stable.
- A manifest is always scoped to **one** partition spec (the one active
  when it was written); when the spec changes, new writes go to new
  manifests under the new spec while old manifests (old spec) are left
  alone. This is why queries get **split planning** — each partition
  layout is planned separately using the filter appropriate to that
  layout, then results are combined.
- v1 compatibility note: v1 didn't track partition field IDs explicitly
  (they were assigned sequentially starting at 1000 in the reference
  implementation). Recommended v1-safe evolution practice: don't reorder
  fields, don't drop fields (replace with the `void` transform instead —
  see [partition-transforms-reference.md](partition-transforms-reference.md)),
  and only add new fields at the end of the previous spec.

# Example

```sql
-- Table with day-level hidden partitioning on event_time
CREATE TABLE logs (level string, message string, event_time timestamp)
USING iceberg
PARTITIONED BY (day(event_time));

-- Evolve: add level as a coarse bucket partition, no rewrite of existing data
ALTER TABLE logs ADD PARTITION FIELD level;
```

```java
// Java API equivalent
Table sampleTable = ...;
sampleTable.updateSpec()
    .addField(bucket("id", 8))
    .removeField("category")
    .commit();
```

# Citations

[1] [Apache Iceberg Documentation — Partitioning](https://iceberg.apache.org/docs/latest/partitioning)
[2] [Apache Iceberg Documentation — Evolution (Partition evolution)](https://iceberg.apache.org/docs/latest/evolution)
[3] [Apache Iceberg Table Spec — Partitioning](https://iceberg.apache.org/spec)
