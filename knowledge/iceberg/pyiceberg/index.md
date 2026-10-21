# Getting Started

* [PyIceberg — Overview and Installation](overview-and-installation.md) - What PyIceberg is (a JVM-free, pure-Python Iceberg implementation), how it differs from PySpark, and pip install extras.
* [PyIceberg — Catalog Configuration](catalog-configuration.md) - Configuring REST/Glue/Hive/SQL/DynamoDB/in-memory catalogs via .pyiceberg.yaml, env vars, or load_catalog().

# Reading and Writing Data

* [PyIceberg — Reading Tables](reading-tables.md) - table.scan(), materializing to pandas/Arrow/DuckDB/Ray/Daft/Polars/Bodo, and time-travel reads.
* [PyIceberg — Writing, Deleting, and Upserting Data](writing-and-upsert.md) - append, overwrite, delete, upsert, transactions, and add_files.
* [PyIceberg — Expression DSL and Row Filter Syntax](expressions-and-row-filters.md) - Composable filter objects (EqualTo, And, Or) vs. the SQL-like string row-filter syntax.

# Schema, Structure, and Tooling

* [PyIceberg — Schema and Partition Evolution](schema-and-partition-evolution.md) - update_schema() and update_spec() transaction APIs for evolving columns and partitioning.
* [PyIceberg — CLI Reference](cli-reference.md) - The pyiceberg command-line tool for listing, describing, and setting properties on namespaces/tables.

# Maintenance

* [PyIceberg — Table Maintenance](maintenance-with-pyiceberg.md) - Snapshot expiration and branch/tag/rollback management from Python; notes that compaction is not yet available in PyIceberg.
