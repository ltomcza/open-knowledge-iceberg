---
type: Iceberg Catalog
title: REST Catalog
description: The vendor-neutral REST Catalog protocol — why it exists, its core concepts and endpoints, and its authentication options.
aliases: [rest catalog, iceberg rest catalog, rest-catalog-spec, RESTCatalog, iceberg-rest-fixture, OpenAPI catalog]
tags: [iceberg, catalog, rest, protocol, auth]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/rest-catalog-spec
---

# Retrieval Notes

Read this first for **the REST catalog protocol conceptually** — why it
exists, what it standardizes, and how auth works. It does not reproduce the
full OpenAPI schema; for the exact request/response shapes, read the
[REST Catalog OpenAPI YAML](https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml)
directly. For catalog properties that configure a REST catalog *client*
(timeouts, caching, auth properties), see the REST-specific tables in
[catalogs-overview.md](/catalogs/catalogs-overview.md#common-catalog-properties)
and below. For catalog selection guidance in general, see
[catalogs-overview.md](/catalogs/catalogs-overview.md).

# Summary

- The REST catalog protocol is a **language- and engine-agnostic HTTP API**
  for catalog operations, defined via an OpenAPI spec — analogous to Hive's
  thrift protocol for the Hive Metastore (HMS), but not tied to any one
  metastore backend.
- It exists because pluggable native catalogs (Hive, Glue, JDBC, ...) each
  needed their own client implementation in every language/engine; REST lets
  any client talk to any catalog through one protocol.
- Any built-in Iceberg catalog can be exposed over REST via the
  `CatalogHandlers` translation class, or by running the community
  [`iceberg-rest-fixture`](https://hub.docker.com/r/apache/iceberg-rest-fixture)
  Docker image — the REST layer is a facade, not a separate storage engine.
- Benefits over talking to a native catalog directly: **server-side
  deconfliction and retries** (change-based commits), simpler **metadata
  version upgrades** (root metadata written by the service), support for
  **lazy snapshot loading**, **multi-table commits**, caching, and secure
  **credential vending / remote signing** for table sharing.
- Auth is pluggable via `rest.auth.type`: `none`, `basic`, `oauth2`, `sigv4`,
  or `google`.
- Explore the spec interactively via the
  [Swagger UI](https://editor-next.swagger.io/?url=https://raw.githubusercontent.com/apache/iceberg/main/open-api/rest-catalog-open-api.yaml).

# Why REST is becoming the standard

Before the REST protocol, every catalog type (Hive, Glue, JDBC, Nessie, ...)
needed a bespoke client implementation per language and per compute engine —
an O(catalogs × languages × engines) integration surface. The REST protocol
collapses this to a single HTTP client implementation per language, which any
REST-compliant catalog server can serve:

- **Language and engine compatibility** — one client works with any catalog.
- **Improved reliability** — change-based commits enable server-side
  deconfliction and automatic retries, reducing commit failures.
- **Simplified metadata management** — the catalog service, not the client,
  writes root metadata, easing version upgrades across the fleet.
- **Advanced features** — lazy snapshot loading, multi-table commits, and
  server-side caching become possible because the server mediates all reads.
- **Security** — supports secure table sharing via credential vending
  (server hands out short-lived storage credentials) or remote signing
  (server signs storage requests on the client's behalf), so clients never
  need long-lived cloud credentials.

# Core concepts

- **Config endpoint** — clients call a config endpoint first to discover
  server capabilities/overrides (e.g. whether server-side scan planning is
  supported) before issuing further requests.
- **Namespaces and tables** — standard CRUD-style endpoints for listing,
  creating, loading, and dropping namespaces and tables, addressed by a
  namespace path and table name.
- **Change-based commits** — table updates are submitted as a list of
  requirements + updates (not a full metadata overwrite), letting the server
  validate and apply them atomically and retry on conflict.
- **Scan planning** — can happen client-side (`CLIENT`, the client reads
  manifests itself) or server-side (`SCAN_PLANNING`/`SERVER`, the server
  returns planned file lists), controlled by the `scan-planning-mode`
  catalog property and overridable per-table by the server response.
- **Pagination** — listing operations (namespaces, tables) support
  page-size-controlled pagination via `rest-page-size`.
- **Views** — the spec also covers view endpoints (SQL views as first-class
  catalog objects), though older servers may not advertise support for them.

# REST catalog client properties

| Property | Default | Description |
|---|---|---|
| `snapshot-loading-mode` | `ALL` | How snapshots are loaded from the server: `ALL` or `REFS` (referenced snapshots only). |
| `rest-metrics-reporting-enabled` | `true` | Whether to report metrics back to the REST server. |
| `view-endpoints-supported` | `false` | Set `true` for backwards compatibility with older servers that support view endpoints but don't advertise them in `endpoints`. |
| `rest-page-size` | null | Page size for listing namespaces, tables, or other paginated resources. |
| `namespace-separator` | `%1F` | Separator character used for namespace levels when communicating with the server. |
| `scan-planning-mode` | `CLIENT` | `CLIENT` (client-side planning) or `SERVER` (server-side planning); can be overridden per-table by the server's `LoadTableResponse`. |

## Table cache properties

Configures a freshness-aware cache for table state, distinct from the
general catalog entry cache in [catalogs-overview.md](/catalogs/catalogs-overview.md):

| Property | Default | Description |
|---|---|---|
| `rest-table-cache.expire-after-write-ms` | `300000` (5 min) | Time after which cached table entries expire. |
| `rest-table-cache.max-entries` | `100` | Maximum number of table entries to cache. |

# Authentication

Set `rest.auth.type` to select a mechanism:

| Property | Default | Description |
|---|---|---|
| `rest.auth.type` | `none` | One of `none`, `basic`, `oauth2`, `sigv4`, `google`. |
| `rest.auth.basic.username` | null | Required if `basic`. |
| `rest.auth.basic.password` | null | Required if `basic`. |
| `rest.auth.sigv4.delegate-auth-type` | `oauth2` | Auth type to delegate to after SigV4 request signing. |

## OAuth2

| Property | Default | Description |
|---|---|---|
| `token` | null | Bearer token to use directly. Either `token` or `credential` is required. |
| `credential` | null | `client_id:client_secret` string exchanged for a token via the client-credentials flow. |
| `oauth2-server-uri` | `v1/oauth/tokens` | Token endpoint, required if the REST catalog itself is not the OAuth2 server. |
| `token-expires-in-ms` | 3600000 (1 hr) | Time after which a bearer token is considered expired. |
| `token-refresh-enabled` | true | Whether tokens are automatically refreshed. |
| `token-exchange-enabled` | true | Whether to use token-exchange to acquire new tokens (falls back to client-credentials if disabled). |
| `scope` | `catalog` | Additional OAuth2 scope. |
| `audience` | null | Optional token `audience` parameter. |
| `resource` | null | Optional `resource` parameter. |

## Google

| Property | Default | Description |
|---|---|---|
| `gcp.auth.credentials-path` | Application Default Credentials | Path to a service account JSON key file. |
| `gcp.auth.credentials-json` | Application Default Credentials | JSON string of a service account credential. |
| `gcp.auth.scopes` | `https://www.googleapis.com/auth/cloud-platform` | Comma-separated OAuth scopes. |

SigV4 signs requests using AWS credentials (for a REST catalog fronted by AWS
infrastructure) and can delegate to a secondary auth type afterward via
`rest.auth.sigv4.delegate-auth-type`.

# Related concepts

- [catalogs-overview.md](/catalogs/catalogs-overview.md) — generic catalog
  properties and how to choose between catalog implementations.
- `/pyiceberg/rest-catalog-client.md` (if present) — PyIceberg's REST client
  usage.

# Citations

[1] [REST Catalog Spec](https://iceberg.apache.org/rest-catalog-spec)
[2] [REST Catalog OpenAPI YAML](https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml)
[3] [Catalog properties — REST catalog properties](https://iceberg.apache.org/docs/latest/catalog-properties)
