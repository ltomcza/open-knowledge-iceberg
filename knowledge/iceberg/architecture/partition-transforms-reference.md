---
type: Iceberg Concept
title: Partition Transforms Reference
description: Full reference of Iceberg's partition transform functions (identity, bucket[N], truncate[W], year, month, day, hour, void) with semantics, source/result types, and when to use each.
aliases: [bucket transform, truncate transform, identity transform, void transform, year month day hour transform, partition transforms]
tags: [iceberg, architecture, partitioning, transforms, reference]
timestamp: 2026-10-22T00:00:00Z
resource: https://iceberg.apache.org/spec
---

# Retrieval Notes

Reference table — read this when choosing or interpreting a specific
transform function. For the surrounding partition-spec concepts, see
[partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md).
Transforms are also used for sort orders — see the "Sorting" note below and
[snapshots-and-versioning.md](snapshots-and-versioning.md) for how sort
order IDs attach to files.

# Summary

- All transforms return `null` for a `null` input.
- `bucket[N]` and `truncate[W]` are parameterized (by bucket count / width);
  the rest are fixed functions.
- Date/time transforms (`year`, `month`, `day`, `hour`) extract calendar
  components as offsets from the epoch, not calendar strings.
- `void` always produces `null` — used to effectively drop a partition
  field in v1 tables without breaking field-ID stability (see
  [partitioning-and-hidden-partitioning.md](partitioning-and-hidden-partitioning.md)
  for why v1 needs this trick).
- The same transform set is reused for **sort orders**, not just partition
  specs.

# Transform Reference Table

| Transform | Description | Valid source types | Result type |
|---|---|---|---|
| `identity` | Source value, unmodified | Any primitive except `geometry` and `geography` | Source type |
| `bucket[N]` | Hash of value, mod `N` | `int`, `long`, `decimal`, `date`, `time`, `timestamp`, `timestamptz`, `timestamp_ns`, `timestamptz_ns`, `string`, `uuid`, `fixed`, `binary` | `int` |
| `truncate[W]` | Value truncated to width `W` | `int`, `long`, `decimal`, `string`, `binary` | Source type |
| `year` | Year, as years since 1970 | `date`, `timestamp`, `timestamptz`, `timestamp_ns`, `timestamptz_ns` | `int` |
| `month` | Month, as months since 1970-01-01 | `date`, `timestamp`, `timestamptz`, `timestamp_ns`, `timestamptz_ns` | `int` |
| `day` | Day, as days since 1970-01-01 | `date`, `timestamp`, `timestamptz`, `timestamp_ns`, `timestamptz_ns` | `date` |
| `hour` | Hour, as hours since 1970-01-01 00:00:00 | `timestamp`, `timestamptz`, `timestamp_ns`, `timestamptz_ns` | `int` |
| `void` | Always `null` | Any | Source type or `int` |

# When to Use Each

| Transform | Use case |
|---|---|
| `identity` | Low-cardinality categorical columns you filter on directly (e.g. `region`, `status`) where no derivation is needed. |
| `bucket[N]` | High-cardinality columns (e.g. `user_id`) where you want even file/partition distribution and don't need range filtering — good for join/co-location strategies and capping partition fan-out. |
| `truncate[W]` | Strings/numbers where you want coarse grouping while preserving prefix range-query pruning (e.g. `truncate[3]` on a product code for a 3-char prefix bucket). |
| `year` / `month` / `day` / `hour` | Timestamp/date columns queried by time range — pick the granularity that matches typical query windows and data volume (e.g. `hour` for high-volume event logs, `month` for slower-growing tables). |
| `void` | v1-only: "remove" a partition field from future use while preserving field ID stability, instead of physically dropping it. |

# Bucket Transform Details

- Uses a 32-bit **Murmur3 hash (x86 variant, seed 0)** of the source value.
- Formula: `bucket_N(x) = (murmur3_x86_32_hash(x) & Integer.MAX_VALUE) % N`
  (the sign bit is discarded before the mod so results are always
  non-negative).
- The number of buckets `N` can be changed later via partition spec
  evolution as a table grows.

# Truncate Transform Details

| Type | Config | Specification | Example |
|---|---|---|---|
| `int` | `W` (width) | `v - (v % W)`, remainder forced positive | `W=10`: `1` → `0`, `-1` → `-10` |
| `long` | `W` (width) | Same as `int` | `W=10`: `1` → `0`, `-1` → `-10` |
| `decimal` | `W` (width, no scale) | `scaled_W = decimal(W, scale(v))`; `v - (v % scaled_W)` | `W=50`, `s=2`: `10.65` → `10.50` |
| `string` | `L` (length) | `v.substring(0, L)`, valid UTF-8, ≤ `L` code points | `L=3`: `iceberg` → `ice` |
| `binary` | `L` (length) | `v.subarray(0, L)` bytes, no assumed encoding | `L=3`: `\x01\x02\x03\x04\x05` → `\x01\x02\x03` |

For languages where `%` can yield negative values, the correct positive
remainder is `v - (((v % W) + W) % W)`.

# Sorting Uses the Same Transforms

Sort orders (per-file, referenced by `sort_order_id` in manifest entries)
reuse the exact same transform functions as partition specs to produce the
value to sort on, combined with a sort direction (`asc`/`desc`) and null
order (`nulls-first`/`nulls-last`). Sort order id `0` is reserved for
"unsorted."

# Citations

[1] [Apache Iceberg Table Spec — Partition Transforms](https://iceberg.apache.org/spec)
[2] [Apache Iceberg Table Spec — Bucket Transform Details](https://iceberg.apache.org/spec)
[3] [Apache Iceberg Table Spec — Truncate Transform Details](https://iceberg.apache.org/spec)
