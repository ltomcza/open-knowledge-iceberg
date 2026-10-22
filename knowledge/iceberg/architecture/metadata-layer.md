---
type: Iceberg Concept
title: Iceberg Metadata Layer — metadata.json
description: Deep dive on the structure of an Iceberg table metadata file (metadata.json) — fields, format-version differences (v1/v2/v3), schemas, partition specs, sort orders, snapshot-log, and metadata-log.
aliases: [metadata.json, table metadata, format version, format-version, iceberg v1 v2 v3, table-uuid, snapshot-log, metadata-log]
tags: [iceberg, architecture, metadata, format-version, spec]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/spec
---

# Retrieval Notes

Read this for the exact fields inside `metadata.json`. For the layer above
this (catalog → metadata.json pointer) see [table-format-overview.md](table-format-overview.md).
For the layer below (manifest list, manifests) see
[manifests-and-manifest-lists.md](manifests-and-manifest-lists.md). For the
`snapshots` list entries specifically, see [snapshots-and-versioning.md](snapshots-and-versioning.md).
For partition-spec and sort-order internals, see
[partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md).

# Summary

- `metadata.json` is a **JSON file** that is the root of a table's state.
  Every change to table state creates a **new** metadata.json file; the old
  one is replaced by an **atomic swap** of the catalog's pointer — never
  mutated in place.
- It carries: `format-version`, `table-uuid`, `location`, the full list of
  **schemas** and the current schema id, the full list of **partition
  specs** and the default spec id, the full list of **sort orders**, the
  list of valid **snapshots**, `current-snapshot-id`, `snapshot-log`,
  `metadata-log`, and `properties`.
- **Format version** (v1/v2/v3, v4 in development) gates which features and
  field requirements apply — each version is additive and backward-readable.
- `snapshot-log` records the history of which snapshot was "current" over
  time; `metadata-log` records the history of previous metadata.json file
  locations — both support time travel and rollback.
- `last-column-id` and `last-partition-id` are monotonically increasing
  counters used to guarantee new columns/partition fields never reuse an ID.

# Format Versions

| Version | Status | Adds |
|---|---|---|
| v1 | Adopted | Analytic tables over immutable Parquet/Avro/ORC files. |
| v2 | Adopted | Row-level deletes via delete files (position + equality deletes); stricter writer requirements; `sequence-number` on snapshots and manifests. |
| v3 | Adopted | New types (`timestamp_ns`/`timestamptz_ns`, `unknown`, `variant`, `geometry`, `geography`); column default values; multi-argument transforms for partitioning/sorting; row lineage tracking; binary deletion vectors (replacing position delete files); table encryption keys. |
| v4 | Under active development, not formally adopted | Adaptive metadata tree: a single root manifest per snapshot replaces the manifest list; data files and their deletion vectors stored in one combined entry (no two-phase planning); relative file locations; writing new equality deletes no longer allowed; new `file` type. (Updated 2026-10-22 from the current spec.) |

All v1 data/metadata remain valid after upgrading a table to v2 — appendix E
of the spec documents how v2 fields default when reading v1 metadata.
Readers must be permissive of older-version metadata; metadata JSON files
themselves may be read more strictly since they always match the table's
actual version (no reuse across versions, unlike manifests).

# Table Metadata Fields

Key fields (requirement varies slightly by format version — see the spec for
the full per-version table):

| Field | Description |
|---|---|
| `format-version` | Integer format version. Readers must reject versions higher than supported. |
| `table-uuid` | UUID generated at table creation; readers must verify it matches on refresh. |
| `location` | Table's base location, used to place data/manifest/metadata files. |
| `last-sequence-number` | Highest assigned sequence number (v2+); tracks snapshot ordering. |
| `last-updated-ms` | Epoch ms timestamp of last update. |
| `last-column-id` | Highest assigned column ID across the table's history — ensures new columns get unused IDs. |
| `schemas` / `current-schema-id` | Full list of schemas ever used, plus which one is current. (`schema` alone is deprecated.) |
| `partition-specs` / `default-spec-id` | Full list of partition specs, plus the default. (`partition-spec` alone is deprecated.) |
| `last-partition-id` | Highest assigned partition field ID — ensures new partition fields get unused IDs. |
| `sort-orders` / `default-sort-order-id` | Full list of sort orders, plus the default. |
| `properties` | String-to-string map of table properties (e.g. `commit.retry.num-retries`). |
| `current-snapshot-id` | ID of the table's current snapshot; must match the `main` branch in `refs`. |
| `snapshots` | List of all valid snapshots (those whose data files still exist). |
| `snapshot-log` | List of `{timestamp, snapshot-id}` pairs recording every change of current snapshot. |
| `metadata-log` | List of `{timestamp, metadata-file-location}` pairs recording prior metadata.json locations. |
| `refs` | Map of snapshot references (branches and tags) — see [branching-and-tagging.md](branching-and-tagging.md). |
| `statistics` / `partition-statistics` | Optional pointers to Puffin statistics files. |
| `next-row-id` (v3+) | Next `_row_id` to assign; supports row lineage tracking. |
| `encryption-keys` (v3+) | Optional list of table encryption keys — see [file-io-and-encryption.md](file-io-and-encryption.md). |

`snapshot-log` and `metadata-log` together are what make **time travel** and
**version rollback** possible: a reader can pick an old snapshot ID or an
old metadata.json location and reconstruct exactly that point-in-time state.

# Commit Model

- Every metadata change writes a **new** `metadata.json`; the previous file
  is never edited in place.
- Commit = atomic swap of the catalog's pointer from the old metadata file
  to the new one (implementation depends on catalog: HDFS atomic rename,
  metastore check-and-put, REST catalog API call, etc.).
- If the swap fails because another writer already committed, the writer
  retries against the new current version — see [reliability-and-concurrency.md](reliability-and-concurrency.md)
  for the optimistic-concurrency protocol and retry rules.

# Example (abridged v2 metadata.json)

```json
{
  "format-version": 2,
  "table-uuid": "9c12d441-03fe-4693-9a96-a0705ddf69c1",
  "location": "s3://bucket/db/table",
  "last-sequence-number": 34,
  "last-updated-ms": 1602638573590,
  "last-column-id": 3,
  "current-schema-id": 1,
  "schemas": [ { "schema-id": 1, "type": "struct", "fields": [ /* ... */ ] } ],
  "default-spec-id": 0,
  "partition-specs": [ { "spec-id": 0, "fields": [ /* ... */ ] } ],
  "last-partition-id": 1000,
  "default-sort-order-id": 0,
  "sort-orders": [ { "order-id": 0, "fields": [] } ],
  "properties": { "commit.retry.num-retries": "4" },
  "current-snapshot-id": 3055729675574597004,
  "snapshots": [ { "snapshot-id": 3055729675574597004, "sequence-number": 34, "...": "..." } ],
  "snapshot-log": [ { "timestamp-ms": 1602638573590, "snapshot-id": 3055729675574597004 } ],
  "metadata-log": [ { "timestamp-ms": 1602638573000, "metadata-file": "s3://bucket/db/table/metadata/v33.metadata.json" } ]
}
```

# Citations

[1] [Apache Iceberg Table Spec — Table Metadata](https://iceberg.apache.org/spec)
[2] [Apache Iceberg Table Spec — Format Versioning (Version 4)](https://iceberg.apache.org/spec/#version-4-metadata-structure-and-representation)
