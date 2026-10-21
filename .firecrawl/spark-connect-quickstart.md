[Skip to main content](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html#main-content)

`Ctrl` + `K`

4.2.0

- [GitHub](https://github.com/apache/spark)
- [PyPI](https://pypi.org/project/pyspark)

# Quickstart: Spark Connect [\#](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html\#Quickstart:-Spark-Connect "Permalink to this headline")

Spark Connect introduced a decoupled client-server architecture for Spark that allows remote connectivity to Spark clusters using the [DataFrame API](https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrame.html?highlight=dataframe#pyspark.sql.DataFrame).

This notebook walks through a simple step-by-step example of how to use Spark Connect to build any type of application that needs to leverage the power of Spark when working with data.

Spark Connect includes both client and server components and we will show you how to set up and use both.

## Launch Spark server with Spark Connect [\#](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html\#Launch-Spark-server-with-Spark-Connect "Permalink to this headline")

To launch Spark with support for Spark Connect sessions, run the `start-connect-server.sh` script.

```
[1]:
```

Copy to clipboard

```
%%bash
source ~/.profile # Make sure environment variables are loaded.
$HOME/sbin/start-connect-server.sh
```

Copy to clipboard

## Connect to Spark Connect server [\#](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html\#Connect-to-Spark-Connect-server "Permalink to this headline")

Now that the Spark server is running, we can connect to it remotely using Spark Connect. We do this by creating a remote Spark session on the client where our application runs. Before we can do that, we need to make sure to stop the existing regular Spark session because it cannot coexist with the remote Spark Connect session we are about to create.

```
[2]:
```

Copy to clipboard

```
from pyspark.sql import SparkSession

SparkSession.builder.master("local[*]").getOrCreate().stop()
```

Copy to clipboard

The command we used above to launch the server configured Spark to run as `localhost:15002`. So now we can create a remote Spark session on the client using the following command.

```
[3]:
```

Copy to clipboard

```
spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
```

Copy to clipboard

## Create DataFrame [\#](https://spark.apache.org/docs/latest/api/python/getting_started/quickstart_connect.html\#Create-DataFrame "Permalink to this headline")

Once the remote Spark session is created successfully, it can be used the same way as a regular Spark session. Therefore, you can create a DataFrame with the following command.

```
[4]:
```

Copy to clipboard

```
from datetime import datetime, date
from pyspark.sql import Row

df = spark.createDataFrame([\
    Row(a=1, b=2., c='string1', d=date(2000, 1, 1), e=datetime(2000, 1, 1, 12, 0)),\
    Row(a=2, b=3., c='string2', d=date(2000, 2, 1), e=datetime(2000, 1, 2, 12, 0)),\
    Row(a=4, b=5., c='string3', d=date(2000, 3, 1), e=datetime(2000, 1, 3, 12, 0))\
])
df.show()
```

Copy to clipboard

```
+---+---+-------+----------+-------------------+
|  a|  b|      c|         d|                  e|
+---+---+-------+----------+-------------------+
|  1|2.0|string1|2000-01-01|2000-01-01 12:00:00|
|  2|3.0|string2|2000-02-01|2000-01-02 12:00:00|
|  4|5.0|string3|2000-03-01|2000-01-03 12:00:00|
+---+---+-------+----------+-------------------+
```

Copy to clipboard

See ‘Live Notebook: DataFrame’ at [the quickstart page](https://spark.apache.org/docs/latest/api/python/getting_started/index.html) for more detail usage of DataFrame API.

On this page


[Show Source](https://spark.apache.org/docs/latest/api/python/_sources/getting_started/quickstart_connect.ipynb.txt)