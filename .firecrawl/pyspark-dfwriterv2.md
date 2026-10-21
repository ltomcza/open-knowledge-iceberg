[Skip to main content](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.html#main-content)

`Ctrl` + `K`

4.2.0

- [GitHub](https://github.com/apache/spark)
- [PyPI](https://pypi.org/project/pyspark)

# pyspark.sql.DataFrameWriterV2 [\#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.html\#pyspark-sql-dataframewriterv2 "Permalink to this headline")

_class_ pyspark.sql.DataFrameWriterV2( _df_, _table_) [\[source\]](https://spark.apache.org/docs/latest/api/python/_modules/pyspark/sql/readwriter.html#DataFrameWriterV2) [#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.html#pyspark.sql.DataFrameWriterV2 "Permalink to this definition")

Interface used to write a class:pyspark.sql.dataframe.DataFrame
to external storage using the v2 API.

New in version 3.1.0.

Changed in version 3.4.0: Supports Spark Connect.

Methods

|     |     |
| --- | --- |
| [`append`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.append.html#pyspark.sql.DataFrameWriterV2.append "pyspark.sql.DataFrameWriterV2.append")() | Append the contents of the data frame to the output table. |
| `clusterBy`(col, \*cols) | Clusters the data by the given columns to optimize query performance. |
| [`create`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.create.html#pyspark.sql.DataFrameWriterV2.create "pyspark.sql.DataFrameWriterV2.create")() | Create a new table from the contents of the data frame. |
| [`createOrReplace`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.createOrReplace.html#pyspark.sql.DataFrameWriterV2.createOrReplace "pyspark.sql.DataFrameWriterV2.createOrReplace")() | Create a new table or replace an existing table with the contents of the data frame. |
| [`option`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.option.html#pyspark.sql.DataFrameWriterV2.option "pyspark.sql.DataFrameWriterV2.option")(key, value) | Add a write option. |
| [`options`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.options.html#pyspark.sql.DataFrameWriterV2.options "pyspark.sql.DataFrameWriterV2.options")(\*\*options) | Add write options. |
| [`overwrite`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.overwrite.html#pyspark.sql.DataFrameWriterV2.overwrite "pyspark.sql.DataFrameWriterV2.overwrite")(condition) | Overwrite rows matching the given filter condition with the contents of the data frame in the output table. |
| [`overwritePartitions`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.overwritePartitions.html#pyspark.sql.DataFrameWriterV2.overwritePartitions "pyspark.sql.DataFrameWriterV2.overwritePartitions")() | Overwrite all partition for which the data frame contains at least one row with the contents of the data frame in the output table. |
| [`partitionedBy`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.html#pyspark.sql.DataFrameWriterV2.partitionedBy "pyspark.sql.DataFrameWriterV2.partitionedBy")(col, \*cols) | Partition the output table created by create, createOrReplace, or replace using the given columns or transforms. |
| [`replace`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.replace.html#pyspark.sql.DataFrameWriterV2.replace "pyspark.sql.DataFrameWriterV2.replace")() | Replace an existing table with the contents of the data frame. |
| [`tableProperty`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.tableProperty.html#pyspark.sql.DataFrameWriterV2.tableProperty "pyspark.sql.DataFrameWriterV2.tableProperty")(property, value) | Add table property. |
| [`using`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.using.html#pyspark.sql.DataFrameWriterV2.using "pyspark.sql.DataFrameWriterV2.using")(provider) | Specifies a provider for the underlying output data source. |

[Show Source](https://spark.apache.org/docs/latest/api/python/_sources/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.rst.txt)