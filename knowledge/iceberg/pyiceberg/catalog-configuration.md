---
type: PyIceberg Guide
title: PyIceberg — Catalog Configuration
description: Configuring PyIceberg catalogs via .pyiceberg.yaml, environment variables, or inline load_catalog() dicts, covering REST, Glue, Hive, SQL, DynamoDB, and in-memory catalogs.
aliases: [pyiceberg catalog config, .pyiceberg.yaml, load_catalog, pyiceberg rest catalog, pyiceberg glue catalog, PYICEBERG_HOME, pyiceberg environment variables]
tags: [pyiceberg, python, catalog, configuration, rest-catalog, glue, hive]
timestamp: 2026-10-22T00:00:00Z
resource: https://py.iceberg.apache.org/configuration
---

# Retrieval Notes

Read this first for "how do I connect PyIceberg to a REST/Glue/Hive/SQL catalog",
"where does PyIceberg read config from", or "how do I set S3/GCS/Azure credentials
for PyIceberg". For general installation see
[overview-and-installation.md](overview-and-installation.md). For catalog-agnostic
Iceberg catalog concepts (protocol, semantics), see
`/catalogs/rest-catalog.md` and sibling catalog concepts elsewhere in this bundle.

# Summary

- Three ways to configure PyIceberg: a `.pyiceberg.yaml` file (recommended),
  environment variables (`PYICEBERG_...`), or properties passed directly to
  `load_catalog(...)`. When several are set, **`load_catalog(**props)` wins over
  environment variables, which win over `.pyiceberg.yaml`** (the source merges
  env vars over the file in `Config.__init__`, then kwargs over both in
  `load_catalog`). Corrected 2026-10-22 — an earlier version implied the file
  took precedence.
- `.pyiceberg.yaml` is searched in `$PYICEBERG_HOME`, then the home directory,
  then the current working directory, in that order.
- Environment variables use double underscore `__` for YAML nesting and single
  underscore `_` converts to dash `-`, e.g. `PYICEBERG_CATALOG__DEFAULT__S3__ACCESS_KEY_ID` sets `s3.access-key-id` on the `default` catalog.
- Natively supported catalog `type` values: `rest`, `sql`, `hive`, `glue`,
  `dynamodb`, `bigquery`. If `type` is omitted, PyIceberg infers it from the
  `uri` scheme (`http(s)` → `rest`, `thrift` → `hive`, `sqlite`/`postgresql`
  → `sql`) and raises an error otherwise — the docs' "defaults to `rest`" only
  holds for HTTP URIs; `in-memory` is a `SqlCatalog` variant backed by in-memory
  SQLite. Any other implementation can be loaded via `py-catalog-impl`.
- REST catalogs support pluggable `auth` blocks (`noop`, `basic`, `oauth2`,
  `custom`, `google`, `entra`) as the modern replacement for legacy OAuth2 fields
  (legacy OAuth2 properties will be removed in PyIceberg 1.0).
- `client.*` properties provide unified AWS credentials shared between Glue/DynamoDB
  catalogs and S3 FileIO; service-specific properties (e.g. `s3.region`) override
  `client.*` when both are set.

# Setting Configuration Values

```bash
export PYICEBERG_CATALOG__DEFAULT__URI=thrift://localhost:9083
export PYICEBERG_CATALOG__DEFAULT__S3__ACCESS_KEY_ID=username
export PYICEBERG_CATALOG__DEFAULT__S3__SECRET_ACCESS_KEY=password
```

Or inline via the Python API — no `.pyiceberg.yaml` required:

```python
from pyiceberg.catalog import load_catalog

catalog = load_catalog(
    "docs",
    **{
        "uri": "http://127.0.0.1:8181",
        "s3.endpoint": "http://127.0.0.1:9000",
        "py-io-impl": "pyiceberg.io.pyarrow.PyArrowFileIO",
        "s3.access-key-id": "admin",
        "s3.secret-access-key": "password",
    }
)
```

Multiple catalogs can coexist in one `.pyiceberg.yaml` and are selected by name:

```yaml
catalog:
  hive:
    uri: thrift://127.0.0.1:9083
    s3.endpoint: http://127.0.0.1:9000
    s3.access-key-id: admin
    s3.secret-access-key: password
  rest:
    uri: https://rest-server:8181/
    warehouse: my-warehouse
```

```python
load_catalog(name="hive")
load_catalog(name="rest")
```

# Catalog Types

| `type` | Notes |
|---|---|
| `rest` | Inferred for `http(s)://` URIs. Iceberg REST protocol. Most cloud-managed catalogs (Glue REST, Unity Catalog, Polaris, Lakekeeper, R2, BigLake, OneLake) speak REST. |
| `sql` | PostgreSQL or SQLite backend via SQLAlchemy. |
| `hive` | Thrift Hive metastore. |
| `glue` | AWS Glue Data Catalog (native, non-REST client). |
| `dynamodb` | AWS DynamoDB-backed catalog. |
| `in-memory` | `SqlCatalog` over in-memory SQLite. Test/demo only, no concurrent access. |
| *(custom)* | Set `py-catalog-impl: mypackage.mymodule.MyCatalog`. |

## REST Catalog

```yaml
catalog:
  default:
    uri: http://rest-catalog/ws/
    credential: t-1234:secret

  default-mtls-secured-catalog:
    uri: https://rest-catalog/ws/
    ssl:
      client:
        cert: /absolute/path/to/client.crt
        key: /absolute/path/to/client.key
      cabundle: /absolute/path/to/cabundle.pem
```

Key REST catalog properties:

| Key | Description |
|---|---|
| `uri` | URI identifying the REST server |
| `warehouse` | Warehouse location/identifier requested from the catalog service |
| `snapshot-loading-mode` | `all` (all snapshots) or `refs` (only snapshots referenced by branches/tags) |
| `header.X-Iceberg-Access-Delegation` | `vended-credentials` (server hands out temp creds) or `remote-signing` (server signs requests) |

Custom headers: any `header.<Header-Name>` property is sent on every HTTP request.

### Pluggable Authentication (`auth` block)

```yaml
catalog:
  default:
    type: rest
    uri: http://rest-catalog/ws/
    auth:
      type: <auth_type>       # noop | basic | oauth2 | custom | google | entra
      <auth_type>:
        # type-specific configuration
      impl: <custom_class_path>   # only for custom
```

| `auth.type` | Config block | Notes |
|---|---|---|
| `noop` | — | No Authorization header sent |
| `basic` | `auth.basic.username` / `.password` | HTTP Basic auth |
| `oauth2` | `auth.oauth2.*` (see below) | OAuth2 client-credentials flow |
| `custom` | `auth.custom.*` + `auth.impl` (required) | Custom `AuthManager` subclass |
| `google` | `auth.google.credentials_path` (optional) | Falls back to Application Default Credentials |
| `entra` | `auth.entra.*` | Falls back to `DefaultAzureCredential`; `pip install pyiceberg[entra-auth]` |

```yaml
auth:
  type: oauth2
  oauth2:
    client_id: my-client-id
    client_secret: my-client-secret
    token_url: https://auth.example.com/oauth/token
    scope: read
    refresh_margin: 60         # optional, seconds before expiry to refresh
    expires_in: 3600           # optional fallback if server omits it
```

Legacy OAuth2 top-level properties (`oauth2-server-uri`, `token`, `credential`,
`scope`, `resource`, `audience`) still work but **will be removed in PyIceberg
1.0** — prefer the `auth` block.

SigV4 signing:

```yaml
rest.sigv4-enabled: true
rest.signing-region: us-east-1
rest.signing-name: execute-api
```

### Common REST-compatible catalog integrations

```yaml
# AWS Glue (as S3 Tables REST endpoint)
catalog:
  s3_tables_catalog:
    type: rest
    uri: https://glue.<region>.amazonaws.com/iceberg
    warehouse: <account-id>:s3tablescatalog/<table-bucket-name>
    rest.sigv4-enabled: true
    rest.signing-name: glue
    rest.signing-region: <region>
```

```yaml
# Databricks Unity Catalog
catalog:
  unity_catalog:
    type: rest
    uri: https://<workspace-url>/api/2.1/unity-catalog/iceberg-rest
    warehouse: <uc-catalog-name>
    token: <databricks-pat-token>
```

```yaml
# Apache Polaris
catalog:
  polaris_catalog:
    type: rest
    uri: https://<account>.snowflakecomputing.com/polaris/api/catalog
    warehouse: <polaris-catalog-name>
    credential: <client-id>:<client-secret>
    header.X-Iceberg-Access-Delegation: vended-credentials
    scope: PRINCIPAL_ROLE:ALL
    token-refresh-enabled: true
    py-io-impl: pyiceberg.io.fsspec.FsspecFileIO
```

Other supported integrations follow the same `type: rest` pattern: Lakekeeper,
Cloudflare R2 Data Catalog, Apache Gravitino, GCP BigLake Metastore, and
Microsoft OneLake (via `auth.type: entra` or a static token).

## SQL Catalog

```yaml
catalog:
  default:
    type: sql
    uri: postgresql+psycopg2://username:password@localhost/mydatabase
    init_catalog_tables: false
```

```yaml
# SQLite — development only, not built for concurrency
catalog:
  default:
    type: sql
    uri: sqlite:////tmp/pyiceberg.db
    init_catalog_tables: false
```

`uri` follows [SQLAlchemy's backend URL format](https://docs.sqlalchemy.org/en/20/core/engines.html#backend-specific-urls).
`init_catalog_tables` defaults to `True` (creates catalog tables on init). `echo`
and `pool_pre_ping` map to the corresponding SQLAlchemy `create_engine` params.

## In-Memory Catalog

```yaml
catalog:
  default:
    type: in-memory
    warehouse: /tmp/pyiceberg/warehouse
```

Built on `SqlCatalog` with an in-memory SQLite backend. Useful for tests, demos,
playgrounds — not production (no concurrent access support).

## Hive Catalog

```yaml
catalog:
  default:
    uri: thrift://localhost:9083
    s3.endpoint: http://localhost:9000
    s3.access-key-id: admin
    s3.secret-access-key: password
```

| Key | Description |
|---|---|
| `hive.hive2-compatible` | Enable Hive 2.x compatibility mode |
| `hive.kerberos-authentication` | Authenticate via Kerberos |
| `hive.kerberos-service-name` | Kerberos service name (default `hive`) |
| `ugi` | Hadoop UGI for the Hive client |

## Glue Catalog

```yaml
catalog:
  default:
    type: glue
    glue.access-key-id: <ACCESS_KEY_ID>
    glue.secret-access-key: <SECRET_ACCESS_KEY>
    glue.session-token: <SESSION_TOKEN>
    glue.region: <REGION_NAME>
    s3.endpoint: http://localhost:9000
    s3.access-key-id: admin
    s3.secret-access-key: password
```

`glue.*` properties are Glue-only. Use `client.*` (below) to share creds with S3
FileIO. Note: `profile_name`, `region_name`, `aws_access_key_id`,
`aws_secret_access_key`, `aws_session_token` were **deprecated and removed in
0.8.0** in favor of `glue.*` / `client.*` prefixed keys.

## DynamoDB Catalog

```yaml
catalog:
  default:
    type: dynamodb
    table-name: iceberg
    dynamodb.access-key-id: <ACCESS_KEY_ID>
    dynamodb.secret-access-key: <SECRET_ACCESS_KEY>
    dynamodb.region: <REGION_NAME>
```

Same deprecation note as Glue applies to unprefixed AWS credential keys.

## Custom Catalog Implementations

```yaml
catalog:
  default:
    py-catalog-impl: mypackage.mymodule.MyCatalog
    custom-key1: value1
    custom-key2: value2
```

# Unified AWS Credentials

`client.*` properties configure credentials for **both** Glue/DynamoDB catalog
calls and S3 FileIO in one place:

```yaml
catalog:
  default:
    type: glue
    client.access-key-id: <ACCESS_KEY_ID>
    client.secret-access-key: <SECRET_ACCESS_KEY>
    client.region: <REGION_NAME>
```

Service-specific properties override `client.*` when both are set (e.g. `s3.region`
wins over `client.region` for S3 FileIO specifically).

# FileIO Backends

PyIceberg auto-selects a FileIO by URI scheme, using the first installed
implementation:

| Scheme | Candidates |
|---|---|
| `s3`, `s3a`, `s3n` | `PyArrowFileIO`, `FsspecFileIO` |
| `gs` | `PyArrowFileIO` |
| `file` | `PyArrowFileIO` |
| `hdfs` | `PyArrowFileIO` |
| `abfs`, `abfss` | `FsspecFileIO` |
| `oss` | `PyArrowFileIO` |
| `hf` | `FsspecFileIO` |

Force a specific implementation with `py-io-impl: pyiceberg.io.fsspec.FsspecFileIO`
(fails loudly if it can't load).

Selected per-backend config keys (see source for full tables): `s3.endpoint`,
`s3.access-key-id`, `s3.secret-access-key`, `s3.region`, `s3.role-arn` (assume-role
via temp creds), `s3.anonymous`; `adls.account-name`, `adls.account-key`,
`adls.sas-token`; `gcs.project-id`, `gcs.oauth2.token`; `hdfs.host`, `hdfs.port`.
OSS (Alibaba Cloud) is accessed via the S3-compatible `S3FileSystem` with
`s3.force-virtual-addressing: true`.

# Table Write Options (table properties)

| Key | Default | Description |
|---|---|---|
| `write.parquet.compression-codec` | `zstd` | `{uncompressed,zstd,gzip,snappy}` |
| `write.parquet.compression-level` | null | Codec compression level |
| `write.parquet.row-group-limit` | 1048576 | Max rows per row group |
| `write.parquet.page-size-bytes` | 1MB | Target page size |
| `write.parquet.page-row-limit` | 20000 | Max rows per page |
| `write.parquet.dict-size-bytes` | 2MB | Dictionary page size limit |
| `write.metadata.previous-versions-max` | 100 | Old metadata files kept after commit |
| `write.metadata.delete-after-commit.enabled` | `False` | Auto-delete old tracked metadata files after commit |
| `write.object-storage.enabled` | `False` | Enables `ObjectStoreLocationProvider` (hashed prefixes) |
| `write.object-storage.partitioned-paths` | `True` | Include partition values in object-store paths |
| `write.data.path` | `{metadata.location}/data` | Data file location |
| `write.metadata.path` | `{metadata.location}/metadata` | Metadata file location |
| `commit.manifest.target-size-bytes` | 8MB | Target size when merging manifests |
| `commit.manifest.min-count-to-merge` | 100 | Min manifests before merging |
| `commit.manifest-merge.enabled` | `False` | Auto-merge manifests on write |

> **Fast append default:** unlike the Java implementation, PyIceberg defaults to
> [fast append](reading-tables.md), so `commit.manifest-merge.enabled` defaults to
> `False`.

# Location Providers

PyIceberg defaults to `SimpleLocationProvider` (Hive-style paths, e.g.
`s3://bucket/ns/table/data/category=orders/....parquet`). Set
`write.object-storage.enabled: True` to use `ObjectStoreLocationProvider`, which
injects deterministic hash directories to spread files across more object-store
prefixes and avoid S3 request throttling on hot prefixes, e.g.:

```
s3://bucket/ns/table/data/0101/0110/1001/10110010/category=orders/0000-...-00001.parquet
```

Set `write.object-storage.partitioned-paths: False` to omit partition
key=value segments entirely for shorter keys. Fully custom providers can be
supplied via `write.py-location-provider.impl: mymodule.MyLocationProvider`
(subclass `LocationProvider`, override `new_data_location` /
`new_metadata_location`).

# Other Settings

- **Manifest cache**: `manifest-cache-size` (default `128` manifests, LRU; `0` disables) or
  `PYICEBERG_MANIFEST_CACHE_SIZE`.
- **Commit retries** (table properties): `commit.retry.num-retries` (4), `min-wait-ms` (100),
  `max-wait-ms` (60000), `total-timeout-ms` (1800000).
- **Isolation** (table properties): `write.delete.isolation-level` / `write.update.isolation-level`,
  default `serializable` — concurrent appends to affected partitions raise `ValidationException`.
- **Concurrency**: `max-workers` in config, or `PYICEBERG_MAX_WORKERS` env var,
  controls the thread pool size for parallel operations.
- **Legacy Java compatibility**: set `legacy-current-snapshot-id: True` (or
  `PYICEBERG_LEGACY_CURRENT_SNAPSHOT_ID`) so tables PyIceberg creates remain
  loadable by old (`<1.4.0`) Java Iceberg clients.
- **Nanosecond timestamps**: PyIceberg only supports microsecond precision.
  `'s'`/`'ms'` PyArrow timestamps are auto-upcast to `'us'` on write;
  `'ns'` timestamps can be auto-downcast by setting
  `downcast-ns-timestamp-to-us-on-write: True` (or the matching env var).

# Citations

[1] [PyIceberg — Configuration](https://py.iceberg.apache.org/configuration)
[2] [apache/iceberg-python — `pyiceberg/utils/config.py` (`Config.__init__`) and `pyiceberg/catalog/__init__.py` (`load_catalog`, `infer_catalog_type`)](https://github.com/apache/iceberg-python/blob/main/pyiceberg/catalog/__init__.py)
