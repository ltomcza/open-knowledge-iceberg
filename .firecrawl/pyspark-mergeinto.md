[Skip to main content](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrame.mergeInto.html#main-content)

`Ctrl` + `K`

4.2.0

- [GitHub](https://github.com/apache/spark)
- [PyPI](https://pypi.org/project/pyspark)

# pyspark.sql.DataFrame.mergeInto [\#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrame.mergeInto.html\#pyspark-sql-dataframe-mergeinto "Permalink to this headline")

DataFrame.mergeInto( _table_, _condition_) [\[source\]](https://spark.apache.org/docs/latest/api/python/_modules/pyspark/sql/dataframe.html#DataFrame.mergeInto) [#](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrame.mergeInto.html#pyspark.sql.DataFrame.mergeInto "Permalink to this definition")

Merges a set of updates, insertions, and deletions based on a source table into
a target table.

New in version 4.0.0.

Parameters**table** str

Target table name to merge into.

**condition** [`Column`](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.Column.html#pyspark.sql.Column "pyspark.sql.Column")

The condition that determines whether a row in the target table matches one in the
source DataFrame.

Returns`MergeIntoWriter`

MergeIntoWriter to use further to specify how to merge the source DataFrame
into the target table.

Notes

This method does not support streaming queries.

Examples

```
>>> from pyspark.sql.functions import expr
>>> source = spark.createDataFrame(
...     [(14, "Tom"), (23, "Alice"), (16, "Bob")], ["id", "name"])
>>> (source.mergeInto("target", "id")
...     .whenMatched().update({ "name": source.name })
...     .whenNotMatched().insertAll()
...     .whenNotMatchedBySource().delete()
...     .merge())
```

Copy to clipboard

[Show Source](https://spark.apache.org/docs/latest/api/python/_sources/reference/pyspark.sql/api/pyspark.sql.DataFrame.mergeInto.rst.txt)