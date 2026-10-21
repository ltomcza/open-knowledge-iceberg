---
type: Reference
title: Iceberg Cheat Sheet — The Three-Page Summary
description: A condensed, memorize-this distillation of the whole bundle — architecture mental model, PySpark day-to-day syntax, and production maintenance/performance rules.
aliases: [iceberg cheat sheet, iceberg summary, iceberg quick reference, iceberg tldr, three page summary]
tags: [iceberg, reference, cheat-sheet, summary, pyspark, maintenance, performance]
timestamp: 2026-08-02T00:00:00Z
---

# Retrieval Notes

This is a **condensed cross-reference**, not a primary source — every fact here is
covered in more depth elsewhere in this bundle. Read this when you want the
handful of ideas worth memorizing, or as a refresher before working with
Iceberg after time away. For the full detail behind any section, follow the
links inline. A nicer-formatted version of this same content also exists as a
published Artifact card, if one was generated for you in conversation.

# Summary

Three parts, matching the structure of the bundle itself: **(I)** the
architecture mental model everything else follows from, **(II)** the PySpark
syntax you'll actually type day to day, and **(III)** the maintenance and
performance rules that keep a table healthy in production.

# I. How Iceberg Actually Works

**The one idea that explains almost everything:** Iceberg tracks the
**complete list of every data file** in a small metadata tree — it never
lists directories to figure out what a table contains. That single design
choice is why Iceberg is safe on object stores, why commits are atomic, why
scan planning is fast at any table size, and why schema/partition changes
don't rewrite data. See
[/architecture/table-format-overview.md](architecture/table-format-overview.md).

**The metadata stack** (each layer narrows down which files a query needs):

```
Catalog            maps namespace.table -> current metadata.json
  -> metadata.json   schemas, partition specs, snapshot list, refs
       -> manifest list   one per snapshot; per-manifest partition stats
            -> manifest file(s)   lists files + per-file column stats
                 -> data / delete file(s)   Parquet / ORC / Avro
```

A commit is nothing more than the catalog atomically swapping which
`metadata.json` it points to. Manifests are usually **reused** across
snapshots — an append writes one new manifest and a new (cheap) manifest
list, not a full rewrite. See
[/architecture/metadata-layer.md](architecture/metadata-layer.md) and
[/architecture/manifests-and-manifest-lists.md](architecture/manifests-and-manifest-lists.md).

**Five things that follow from that:**

| Concept | What it means in practice |
|---|---|
| **Snapshots** | Every write/delete/compaction = one new snapshot = one atomic, all-or-nothing state. Readers see a consistent snapshot with zero locking. Old snapshots enable time travel and rollback until expired. See [/architecture/snapshots-and-versioning.md](architecture/snapshots-and-versioning.md). |
| **Hidden partitioning** | Partition values are *derived* from a column transform (`days(ts)`), not user-supplied. You filter on `ts`; Iceberg does the partition pruning itself — removes the classic Hive failure mode of a wrong/forgotten partition filter silently returning wrong results. See [/architecture/partitioning-and-hidden-partitioning.md](architecture/partitioning-and-hidden-partitioning.md). |
| **Schema evolution** | Add/drop/rename/reorder/widen columns are pure metadata edits — no data rewrite, ever. Safe because every field has a permanent column ID; data is resolved by ID, never name or position, so a rename can never "resurrect" old data. See [/architecture/schema-evolution.md](architecture/schema-evolution.md). |
| **Row-level deletes** | Copy-on-write (COW): rewrite the affected file immediately — cheap reads, costly writes. Merge-on-read (MOR): write a small delete file/vector, merge at read time — cheap writes, needs periodic compaction. See [/architecture/row-level-deletes.md](architecture/row-level-deletes.md). |
| **Optimistic concurrency** | Writers assume they're alone, build new metadata, then try an atomic pointer swap. Loser retries against the new state. Appends almost always retry safely; replace/delete/schema changes must re-validate first. See [/architecture/reliability-and-concurrency.md](architecture/reliability-and-concurrency.md). |

**Branches & tags** — a **tag** is a fixed label on one snapshot, never
moves; a **branch** is an independent, moving lineage, like a second `main`.
**Write-Audit-Publish (WAP):** write to an isolated branch, validate the
data, then `fast_forward` main onto it — production readers never see
unvalidated writes. See
[/architecture/branching-and-tagging.md](architecture/branching-and-tagging.md).

**Picking a catalog** — its only real job is an atomic compare-and-swap on
the metadata pointer. **REST** is the recommended default (vendor-neutral);
**Hive Metastore** for existing Hadoop shops; **Glue** for AWS-native
stacks; **Nessie** for git-like branching across the whole catalog; **JDBC**
to reuse an existing Postgres/MySQL. See
[/catalogs/catalogs-overview.md](catalogs/catalogs-overview.md).

> **Remember:** No listing, ever — planning reads metadata, not
> directories. A commit is one atomic pointer swap, nothing is ever
> half-visible. Column identity is a permanent ID, so renaming is never
> risky. MOR trades write cost for read cost, and compaction repays that
> debt. `main` never expires — every other branch/tag should have a
> retention age.

# II. PySpark, Day to Day

**Minimal setup** (catalog name `local`, warehouse `/tmp/warehouse`, as used
throughout the tutorials):

```python
spark = (SparkSession.builder
    .config("spark.jars.packages",
            "org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0")
    .config("spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.local.type", "hadoop")
    .config("spark.sql.catalog.local.warehouse", "/tmp/warehouse")
    .config("spark.sql.defaultCatalog", "local")
    .getOrCreate())
```

Forgetting `spark.sql.extensions` is the #1 cause of "`CALL`/`MERGE INTO`
doesn't work" — most DDL still runs without it, so the failure shows up
later than you'd expect. See
[/pyspark/setup-and-configuration.md](pyspark/setup-and-configuration.md).

**Writing** — see [/pyspark/writing-data.md](pyspark/writing-data.md):

| `writeTo(...)` | SQL equivalent | Does |
|---|---|---|
| `.append()` | `INSERT INTO` | Add rows |
| `.overwritePartitions()` | `INSERT OVERWRITE` (dynamic) | Replace exactly the partitions touched by the data — **recommended default** |
| `.overwrite(filter)` | `INSERT OVERWRITE ... PARTITION(...)` (static) | Replace rows matching a filter |
| `.create()` / `.replace()` / `.createOrReplace()` | `CREATE/REPLACE TABLE AS SELECT` | New table from a DataFrame |

Prefer `writeTo(...)` over the legacy `df.write.format("iceberg")` — the old
path can load a stale, non-refreshing table reference. For upserts, prefer
**`MERGE INTO` over `INSERT OVERWRITE`**: it only rewrites the files that
actually changed and keeps working correctly across partition-spec
evolution. See
[/pyspark/merge-into-and-row-level-operations.md](pyspark/merge-into-and-row-level-operations.md).

```python
spark.sql("""
MERGE INTO prod.db.target t
USING (SELECT ...) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.data = s.data
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE   -- full-state sync / hard deletes
""")
```

> **Pitfall:** a source row that matches more than one target row throws at
> runtime. Dedupe the source (`ROW_NUMBER()`, `first()`) before merging,
> especially with CDC batches.

**Reading & time travel** — see
[/pyspark/reading-data-and-queries.md](pyspark/reading-data-and-queries.md):

| Query | Uses schema of |
|---|---|
| `... VERSION AS OF <snapshot-id>` | that snapshot |
| `... TIMESTAMP AS OF '<ts>'` | the snapshot current at that time |
| `... VERSION AS OF '<tag>'` | the tag's snapshot |
| `... VERSION AS OF '<branch>'` | the table's **current** schema (new columns read as `NULL` on old rows) |

Inspect anything by suffixing the table name: `.snapshots` · `.history` ·
`.files` · `.manifests` · `.partitions` · `.entries` · `.refs`. Prefix with
`all_` to see every tracked snapshot, not just current.

```python
spark.sql("SELECT * FROM local.db.people.snapshots")
spark.sql("SELECT * FROM local.db.people.files")
```

**The `CALL` procedures worth knowing cold** — full syntax in
[/pyspark/spark-procedures.md](pyspark/spark-procedures.md):

| Procedure | Use it to |
|---|---|
| `rollback_to_snapshot` / `rollback_to_timestamp` | Actually revert `main` to an earlier state (not just query it) |
| `rewrite_data_files` | Compact small files; `strategy => 'sort'` or `sort_order => 'zorder(...)'` for clustering |
| `expire_snapshots` | Reclaim storage — deletes files no live snapshot needs anymore |
| `remove_orphan_files` | Clean up files never committed (crashed/failed writers) — run `dry_run => true` first |
| `rewrite_manifests` | Re-cluster manifests after heavy compaction, for faster future planning |
| `fast_forward` | Publish a validated WAP branch onto `main` |
| `create_changelog_view` | Turn a snapshot range into an INSERT/UPDATE/DELETE change feed (CDC) |

```python
spark.sql("CALL local.system.rewrite_data_files('db.people')")
spark.sql("CALL local.system.expire_snapshots('db.people', retain_last => 5)")
spark.sql("CALL local.system.remove_orphan_files(table => 'db.people', dry_run => true)")
```

> **Remember:** No `spark.sql.extensions` means no `CALL`, no `MERGE` — set
> it every time. Dynamic overwrite is the sane default; static overwrite
> can't see hidden partitions. `MERGE INTO` beats `INSERT OVERWRITE` for
> upserts, always. `<table>.snapshots` / `.files` / `.history` is the
> fastest way to debug what a job actually wrote. Every maintenance action
> is just a `CALL` — no separate tooling needed.

# III. Running It in Production

**Why a scan is fast (or isn't)** — planning happens in two pruning passes,
both over metadata, never over the data itself: first the **manifest list**
eliminates whole manifests using per-manifest partition ranges, then
surviving **manifests** eliminate individual files using per-file column
min/max bounds. A well-laid-out multi-petabyte table can be planned from a
single node. See
[/performance/performance-overview.md](performance/performance-overview.md).

| Fast when… | Slow when… |
|---|---|
| Query predicate matches the partition columns | Predicate only touches non-partition columns |
| Data is clustered → tight per-file min/max | Data scattered → every file's range spans the whole table |
| Files are well-sized (compacted) | Many small files → bloated manifests, more entries to open |

**The maintenance loop, in order** — see
[/maintenance/maintenance-scheduling-and-strategy.md](maintenance/maintenance-scheduling-and-strategy.md):

1. **Compact** (`rewrite_data_files`) — fixes the file layout, the highest-leverage lever you have.
2. **Rewrite manifests** — re-index the new layout; cheap, metadata-only.
3. **Expire snapshots** — now the intermediate compaction snapshots are eligible too.
4. **Remove orphan files** — final sweep for anything that never made it into a snapshot.

Running these out of order wastes work — e.g. expiring before compacting
just means re-expiring again once compaction produces its own snapshots.

| Table profile | Compaction | Expire / orphan cleanup |
|---|---|---|
| Streaming / micro-batch | 15 min – hourly, scoped with `where` | Daily |
| Multiple batch loads/day | Every few hours or per load | Daily |
| Daily batch | Daily, after the load | Weekly |
| Slow-changing | Weekly or trigger-based | Monthly |

**Partitioning, sort order, z-order — pick correctly:**

- **Partition** on the column your queries actually filter by, sized so a
  typical query excludes most partitions *and* each partition still fills a
  reasonably-sized file. Over-fine → small-files problem; too coarse →
  pruning does nothing. See
  [/performance/partitioning-strategy-for-performance.md](performance/partitioning-strategy-for-performance.md).
- **Sort order** tightens the min/max bounds for its leading column — use
  when one column dominates your filters.
- **Z-order** spreads clustering benefit evenly across several columns —
  use when queries filter on varying combinations, no single column
  dominant. See
  [/performance/sort-order-and-file-layout.md](performance/sort-order-and-file-layout.md).
- Got the partition spec wrong? **Evolve it** — old files keep their old
  layout, new files use the new spec, both are queried together. Never a
  full rewrite.

**PyIceberg — when to skip Spark entirely.** Pure Python, **no JVM** — a
genuinely different codebase from PySpark's Java core underneath. Reach for
it in notebooks, pandas/Polars/DuckDB pipelines, or embedding Iceberg
reads/writes inside a Python service without standing up a cluster. Keep
using Spark for large distributed compute and heavy maintenance —
**compaction is not yet available in PyIceberg.** See
[/pyiceberg/overview-and-installation.md](pyiceberg/overview-and-installation.md).

> **Remember:** Compaction is the single highest-leverage maintenance job —
> schedule it before anything else. Cadence tracks commit frequency, not
> table size. Sort for one dominant filter column; z-order for several
> competing ones. A bad initial partition spec is fixable via evolution —
> don't over-invest upfront. PyIceberg for lightweight Python access,
> PySpark for scale and maintenance.

# Citations

This page condenses material documented in full elsewhere in this bundle —
see the linked concept pages above for primary sourcing. Underlying sources:
[Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest),
[Apache Iceberg Table Spec](https://iceberg.apache.org/spec),
[PyIceberg Documentation](https://py.iceberg.apache.org).
