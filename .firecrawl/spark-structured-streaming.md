[Skip to content](https://iceberg.apache.org/docs/latest/spark-structured-streaming/#spark-structured-streaming)

# Spark Structured Streaming [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#spark-structured-streaming "Permanent link")

Iceberg uses Apache Spark's DataSourceV2 API for data source and catalog implementations. Spark DSv2 is an evolving API with different levels of support in Spark versions.

## Streaming Reads [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#streaming-reads "Permanent link")

Iceberg supports processing incremental data in spark structured streaming jobs which starts from a historical timestamp:

```
val df = spark.readStream
    .format("iceberg")
    .option("stream-from-timestamp", Long.toString(streamStartTimestamp))
    .load("database.table_name")
```

Warning

Iceberg only supports reading data from append snapshots. Overwrite snapshots cannot be processed and will cause an exception by default. Overwrites may be ignored by setting `streaming-skip-overwrite-snapshots=true`. Similarly, delete snapshots will cause an exception by default, and deletes may be ignored by setting `streaming-skip-delete-snapshots=true`.

### Limit input rate [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#limit-input-rate "Permanent link")

To control the size of micro-batches in the DataFrame API, Iceberg supports two read options:

- `streaming-max-files-per-micro-batch` Maximum number of files to be processed in every micro-batch.
- `streaming-max-rows-per-micro-batch` A "soft max" on the number of rows to be processed in every micro-batch. A batch will always include all the rows in the next unprocessed data file but additional files will not be included if doing so would exceed the soft max limit.

If both options are set, the micro-batch size will be limited by whichever option is reached first.

```
// Read a hard limit of 1 file per micro-batch
val df = spark.readStream
    .format("iceberg")
    .option("streaming-max-files-per-micro-batch", "1")
    .load("database.table_name")
```

```
// Read files until the number of included rows >= 1000 per micro-batch
val df = spark.readStream
    .format("iceberg")
    .option("streaming-max-rows-per-micro-batch", "1000")
    .load("database.table_name")
```

Info

Note: In addition to limiting micro-batch sizes on queries that use the default trigger (i.e. `Trigger.ProcessingTime`), rate limiting options can be applied to queries that use `Trigger.AvailableNow` to split one-time processing of all available source data into multiple micro-batches for better query scalability. Rate limiting options will be ignored when using the deprecated `Trigger.Once` trigger.

### Asynchronous Micro-Batch Planning [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#asynchronous-micro-batch-planning "Permanent link")

Users can enable asynchronous micro-batch planning by setting `async-micro-batch-planning-enabled` to true. With this option enabled, Iceberg will start processing the current micro-batch while planning the next micro-batches in parallel.
This can help improve query throughput by reducing idle time between micro-batches. Users should weigh the tradeoffs, which include higher memory usage and increased snapshot detection latency.

Users can also set additional options to control the behavior of asynchronous micro-batch planning, found in the [spark configuration](https://iceberg.apache.org/docs/latest/spark-configuration/#read-options).

## Streaming Writes [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#streaming-writes "Permanent link")

To write values from streaming query to Iceberg table, use `DataStreamWriter`:

```
data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(Trigger.ProcessingTime(1, TimeUnit.MINUTES))
    .option("checkpointLocation", checkpointPath)
    .toTable("database.table_name")
```

In the case of the directory-based Hadoop catalog:

```
data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(Trigger.ProcessingTime(1, TimeUnit.MINUTES))
    .option("path", "hdfs://nn:8020/path/to/table")
    .option("checkpointLocation", checkpointPath)
    .start()
```

Iceberg supports `append` and `complete` output modes:

- `append`: appends the rows of every micro-batch to the table
- `complete`: replaces the table contents every micro-batch

Prior to starting the streaming query, ensure you created the table. Refer to the [SQL create table](https://iceberg.apache.org/docs/latest/spark-ddl/#create-table) documentation to learn how to create the Iceberg table.

Iceberg doesn't support experimental [continuous processing](https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html#continuous-processing), as it doesn't provide the interface to "commit" the output.

### Partitioned table [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#partitioned-table "Permanent link")

Iceberg requires sorting data by partition per task prior to writing the data. In Spark tasks are split by Spark partition
against partitioned table. For batch queries you're encouraged to do explicit sort to fulfill the requirement
(see [here](https://iceberg.apache.org/docs/latest/spark-writes/#writing-distribution-modes)), but the approach would bring additional latency as
repartition and sort are considered as heavy operations for streaming workload. To avoid additional latency, you can
enable fanout writer to eliminate the requirement.

```
data.writeStream
    .format("iceberg")
    .outputMode("append")
    .trigger(Trigger.ProcessingTime(1, TimeUnit.MINUTES))
    .option("fanout-enabled", "true")
    .option("checkpointLocation", checkpointPath)
    .toTable("database.table_name")
```

Fanout writer opens the files per partition value and doesn't close these files till the write task finishes. Avoid using the fanout writer for batch writing, as explicit sort against output rows is cheap for batch workloads.

## Maintenance for streaming tables [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#maintenance-for-streaming-tables "Permanent link")

Streaming writes can create new table versions quickly, creating lots of table metadata to track those versions.
Maintaining metadata by tuning the rate of commits, expiring old snapshots, and automatically cleaning up metadata files
is highly recommended.

### Tune the rate of commits [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#tune-the-rate-of-commits "Permanent link")

Having a high rate of commits produces data files, manifests, and snapshots which leads to additional maintenance. It is recommended to have a trigger interval of 1 minute at the minimum and increase the interval if needed.

The triggers section in [Structured Streaming Programming Guide](https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html#triggers)
documents how to configure the interval.

### Expire old snapshots [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#expire-old-snapshots "Permanent link")

Each batch written to a table produces a new snapshot. Iceberg tracks snapshots in table metadata until they are expired. Snapshots accumulate quickly with frequent commits, so it is highly recommended that tables written by streaming queries are [regularly maintained](https://iceberg.apache.org/docs/latest/maintenance/#expire-snapshots). [Snapshot expiration](https://iceberg.apache.org/docs/latest/spark-procedures/#expire_snapshots) is the procedure of removing the metadata and any data files that are no longer needed. By default, the procedure will expire the snapshots older than five days.

### Compacting data files [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#compacting-data-files "Permanent link")

The amount of data written from a streaming process is typically small, which can cause the table metadata to track lots of small files. [Compacting small files into larger files](https://iceberg.apache.org/docs/latest/maintenance/#compact-data-files) reduces the metadata needed by the table, and increases query efficiency. Iceberg and Spark [comes with the `rewrite_data_files` procedure](https://iceberg.apache.org/docs/latest/spark-procedures/#rewrite_data_files).

### Rewrite manifests [🔗](https://iceberg.apache.org/docs/latest/spark-structured-streaming/\#rewrite-manifests "Permanent link")

To optimize write latency on a streaming workload, Iceberg can write the new snapshot with a "fast" append that does not automatically compact manifests.
This could lead lots of small manifest files. Iceberg can [rewrite the number of manifest files to improve query performance](https://iceberg.apache.org/docs/latest/maintenance/#rewrite-manifests). Iceberg and Spark [come with the `rewrite_manifests` procedure](https://iceberg.apache.org/docs/latest/spark-procedures/#rewrite_manifests).

Back to top