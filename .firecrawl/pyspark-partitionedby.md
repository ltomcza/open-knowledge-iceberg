[Skip to main content](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.html#main-content)

`Ctrl` + `K`

4.2.0

- [GitHub](https://github.com/apache/spark)
- [PyPI](https://pypi.org/project/pyspark)

# pyspark.sql.DataFrameWriterV2.partitionedBy [\#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.html\#pyspark-sql-dataframewriterv2-partitionedby "Permalink to this headline")

DataFrameWriterV2.partitionedBy( _col_, _\*cols_) [\[source\]](https://spark.apache.org/docs/latest/api/python/_modules/pyspark/sql/readwriter.html#DataFrameWriterV2.partitionedBy) [#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.html#pyspark.sql.DataFrameWriterV2.partitionedBy "Permalink to this definition")

Partition the output table created by create, createOrReplace, or replace using
the given columns or transforms.

When specified, the table data will be stored by these values for efficient reads.

For example, when a table is partitioned by day, it may be stored
in a directory layout like:

- table/day=2019-06-01/

- table/day=2019-06-02/


Partitioning is one of the most widely used techniques to optimize physical data layout.
It provides a coarse-grained index for skipping unnecessary data reads when queries have
predicates on the partitioned columns. In order for partitioning to work well, the number
of distinct values in each column should typically be less than tens of thousands.

col and cols support only the following functions:

- `pyspark.sql.functions.years()`

- `pyspark.sql.functions.months()`

- `pyspark.sql.functions.days()`

- `pyspark.sql.functions.hours()`

- `pyspark.sql.functions.bucket()`


[Show Source](https://spark.apache.org/docs/latest/api/python/_sources/reference/pyspark.sql/api/pyspark.sql.DataFrameWriterV2.partitionedBy.rst.txt)