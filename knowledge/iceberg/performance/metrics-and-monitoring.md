---
type: Performance Guide
title: Metrics and Monitoring
description: Iceberg's MetricsReporter/MetricsReport interface — scan and commit metrics — and how to hook it up for observability.
aliases: [MetricsReporter, MetricsReport, ScanReport, CommitReport, metrics-reporter-impl, observability, LoggingMetricsReporter]
tags: [iceberg, performance, monitoring, metrics, observability]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/metrics-reporting/
---

# Retrieval Notes

Read this when instrumenting production Iceberg tables for observability —
tracking scan planning cost or commit health over time, or building
dashboards/alerts. Complements
[/performance/performance-overview.md](/performance/performance-overview.md)
(what these metrics measure conceptually) and
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md)
(using commit/scan metrics to decide when maintenance is needed).

# Summary

- As of Iceberg 1.1.0, the `MetricsReporter` / `MetricsReport` APIs provide
  a pluggable way to receive metrics about scans and commits.
- Two report types: **`ScanReport`** (metrics from scan planning) and
  **`CommitReport`** (metrics from committing a snapshot).
- Built-in reporters: **`LoggingMetricsReporter`** (default — logs reports
  to the application log) and **`RESTMetricsReporter`** (default when using
  `RESTCatalog` — POSTs reports to the catalog's REST metrics endpoint).
- Custom reporters implement `MetricsReporter.report(MetricsReport)` and
  can forward to any observability system (Prometheus, etc.).
- Registration is via the catalog property `metrics-reporter-impl`
  (fully-qualified class name), or supplied ad hoc per-scan through the
  Java API's `TableScan.metricsReporter(...)`.

# Report Types

## ScanReport

Emitted per scan-planning operation. Carries table identity (table name,
snapshot ID) plus:

- Total scan planning duration
- Number of data/delete files included in the result
- Number of data/delete manifests scanned vs skipped
- Number of data/delete files scanned vs skipped
- Number of equality/positional delete files scanned

This directly measures how effective the metadata-based pruning described
in
[/performance/performance-overview.md](/performance/performance-overview.md)
is being in practice — a high ratio of *skipped* to *scanned* manifests/files
indicates pruning is working well; a low ratio suggests partitioning, sort
order, or manifest organization may need attention.

## CommitReport

Emitted after a commit (new snapshot). Carries table identity plus:

- Total commit duration
- Number of attempts required to succeed (commit retries)
- Number of added/removed data and delete files
- Number of added/removed equality/positional delete files and delete
  counts

Useful for tracking write-side health: rising commit attempt counts
indicate contention (concurrent writers retrying), and file-count deltas
over time are a leading indicator of small-file accumulation before it
shows up as a scan-performance problem — feeding directly into the cadence
decisions in
[/maintenance/maintenance-scheduling-and-strategy.md](/maintenance/maintenance-scheduling-and-strategy.md).

# Built-In Reporters

| Reporter | When used | Behavior |
|---|---|---|
| `LoggingMetricsReporter` | Default when nothing else is configured | Logs each report to the application log file as a structured text dump |
| `RESTMetricsReporter` | Default when using `RESTCatalog` | Sends reports to the catalog's REST endpoint (`/v1/{prefix}/namespaces/{namespace}/tables/{table}/metrics`); toggle with `rest-metrics-reporting-enabled` (default `true`) |

Example `LoggingMetricsReporter` output shape (abbreviated):

```
ScanReport{
    tableName=..., snapshotId=2, filter=...,
    scanMetrics=ScanMetricsResult{
        totalPlanningDuration=...,
        resultDataFiles=..., resultDeleteFiles=...,
        totalDataManifests=..., scannedDataManifests=..., skippedDataManifests=...,
        totalFileSizeInBytes=..., skippedDataFiles=..., skippedDeleteFiles=...}}

CommitReport{
    tableName=..., snapshotId=1, operation=append,
    commitMetrics=CommitMetricsResult{
        totalDuration=..., attempts=...,
        addedDataFiles=..., totalDataFiles=..., addedRecords=..., totalRecords=...}}
```

# Implementing and Registering a Custom Reporter

Implement `MetricsReporter`:

```java
public class InMemoryMetricsReporter implements MetricsReporter {
  private List<MetricsReport> metricsReports = Lists.newArrayList();

  @Override
  public void report(MetricsReport report) {
    metricsReports.add(report);
  }

  public List<MetricsReport> reports() {
    return metricsReports;
  }
}
```

This is the extension point for forwarding to Prometheus or any other
observability/metrics system — the interface just receives report objects;
what you do with them (log, export, aggregate) is entirely up to the
implementation.

Register at the catalog level (applies to all scans/commits through that
catalog):

```
metrics-reporter-impl=org.apache.iceberg.metrics.InMemoryMetricsReporter
```

Or supply additional reporters ad hoc for a specific scan, independent of
the catalog-level reporter:

```java
TableScan tableScan =
    table.newScan()
        .metricsReporter(customReporterOne)
        .metricsReporter(customReporterTwo);

try (CloseableIterable<FileScanTask> fileScanTasks = tableScan.planFiles()) {
  // ...
}
```

# Citations

[1] [Apache Iceberg — Metrics Reporting](https://iceberg.apache.org/docs/latest/metrics-reporting/)
