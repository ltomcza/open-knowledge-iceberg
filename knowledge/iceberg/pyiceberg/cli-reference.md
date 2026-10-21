---
type: PyIceberg Guide
title: PyIceberg — CLI Reference
description: The pyiceberg command-line tool — listing namespaces/tables, describing tables, inspecting schema, and getting/setting properties, including JSON output for automation.
aliases: [pyiceberg cli, pyiceberg command line, pyiceberg describe, pyiceberg list, pyiceberg properties, pyiceberg schema command]
tags: [pyiceberg, python, cli, command-line]
timestamp: 2026-07-31T00:00:00Z
resource: https://py.iceberg.apache.org/cli
---

# Retrieval Notes

Read this first for "PyIceberg CLI commands", "how do I inspect a table from the
terminal without writing Python", or "pyiceberg describe/list/properties". For
programmatic (Python API) equivalents of inspection, see
[reading-tables.md](reading-tables.md#inspecting-table-metadata). For catalog
setup the CLI relies on, see
[catalog-configuration.md](catalog-configuration.md).

# Summary

- The `pyiceberg` CLI ships with the `pyiceberg` package — no extra install step.
- Catalog selection: use `--catalog <name>` to pick from `.pyiceberg.yaml`, or
  pass `--uri`/`--credential` directly; a `~/.pyiceberg.yaml` config is
  recommended over passing connection args every time.
- `--output json` switches all commands to machine-readable JSON, useful piped
  into `jq` for automation/scripting.
- Core commands: `list`, `describe`, `schema`, `spec`, `files`, `list-refs`,
  `location`, `uuid`, `rename`, `drop`, `create`, `properties` (get/set/remove).

# Global Options

```
pyiceberg --help
```

```
Usage: pyiceberg [OPTIONS] COMMAND [ARGS]...

Options:
  --catalog TEXT
  --verbose BOOLEAN
  --output [text|json]
  --ugi TEXT
  --uri TEXT
  --credential TEXT
  --help                Show this message and exit.

Commands:
  create      Operation to create a namespace.
  describe    Describe a namespace or a table.
  drop        Operations to drop a namespace or table.
  files       List all the files of the table.
  list        List tables or namespaces.
  list-refs   List all the refs in the provided table.
  location    Return the location of the table.
  properties  Properties on tables/namespaces.
  rename      Rename a table.
  schema      Get the schema of the table.
  spec        Return the partition spec of the table.
  uuid        Return the UUID of the table.
  version     Print pyiceberg version.
```

Use `--catalog <name>` to select a non-default catalog defined in
`.pyiceberg.yaml` (e.g. `--catalog rest`).

# Listing Namespaces and Tables

```bash
pyiceberg list
# default
# nyc

pyiceberg list nyc
# nyc.taxis
```

# Describing a Table

```bash
pyiceberg describe nyc.taxis
```

```
Table format version  1
Metadata location     file:/.../nyc.db/taxis/metadata/00000-....metadata.json
Table UUID            6cdfda33-bfa3-48a7-a09e-7abb462e3460
Last Updated          1661783158061
Partition spec        []
Sort order            []
Current schema        Schema, id=0
├── 1: VendorID: optional long
├── 2: tpep_pickup_datetime: optional timestamptz
...
Current snapshot      Operation.APPEND: id=5937117119577207079, schema_id=0
Snapshots             Snapshots
└── Snapshot 5937117119577207079, schema 0: file:/.../snap-....avro
Properties            owner                 root
write.format.default  parquet
```

## JSON output for automation

```bash
pyiceberg --output json describe nyc.taxis | jq
```

Returns the full table metadata JSON — identifier, `metadata_location`, schemas,
partition specs, snapshots, snapshot-log, metadata-log, sort-orders, and `refs`
(branch/tag -> snapshot-id mapping). Suitable for scripting/CI checks against
table state.

# Managing Properties

Set, get, and remove properties on tables (or namespaces):

```bash
pyiceberg properties set table nyc.taxis write.metadata.delete-after-commit.enabled true
# Set write.metadata.delete-after-commit.enabled=true on nyc.taxis

pyiceberg properties get table nyc.taxis
# write.metadata.delete-after-commit.enabled  true

pyiceberg properties remove table nyc.taxis write.metadata.delete-after-commit.enabled
# Property write.metadata.delete-after-commit.enabled removed from nyc.taxis

pyiceberg properties get table nyc.taxis write.metadata.delete-after-commit.enabled
# Could not find property write.metadata.delete-after-commit.enabled on nyc.taxis
```

# Other Commands (by name)

| Command | Purpose |
|---|---|
| `create` | Create a namespace |
| `drop` | Drop a namespace or a table |
| `schema` | Print a table's current schema |
| `spec` | Print a table's partition spec |
| `files` | List all files belonging to a table |
| `list-refs` | List all branches/tags (refs) on a table |
| `location` | Print a table's root location |
| `uuid` | Print a table's UUID |
| `rename` | Rename a table |
| `version` | Print the installed PyIceberg version |

# Citations

[1] [PyIceberg — Python CLI](https://py.iceberg.apache.org/cli)
