---
type: Iceberg Concept
title: FileIO and Table Encryption
description: The FileIO abstraction that decouples Iceberg from specific storage systems, and an overview of Iceberg's native table encryption (KMS integration, key wrapping, encrypted file formats).
aliases: [FileIO, iceberg storage abstraction, table encryption, KMS, encryption.key-id, key management client, PARE, AGS1]
tags: [iceberg, architecture, fileio, encryption, storage, security]
timestamp: 2026-07-31T00:00:00Z
resource: https://iceberg.apache.org/docs/latest/fileio
---

# Retrieval Notes

Read this for how Iceberg talks to storage generically, and how table
encryption layers on top. For where encryption key metadata is persisted in
table metadata, see [metadata-layer.md](metadata-layer.md) (`encryption-keys`)
and [manifests-and-manifest-lists.md](manifests-and-manifest-lists.md)
(`key_metadata` on data files and manifests). For catalog-specific
encryption support, see `/catalogs/rest-catalog.md` and
`/catalogs/hive-metastore.md`.

# Summary

- **FileIO** is the interface Iceberg uses for **all** metadata operations
  (job planning, commits) and is the abstraction layer that lets the same
  Iceberg core work across S3, GCS, ADLS/Azure, Hadoop-compatible file
  systems, and other object stores — implementations only need read, write,
  and seek.
  Data files themselves are read/written by the **processing engine**, not
  FileIO directly; FileIO's job is metadata files (and it captures the new
  table state that engines write after data files land).
- Iceberg tracks **absolute paths** for data files in metadata, so file
  layout is decoupled from any single storage assumption, and there is
  never a rename in the write path (v1-v3; v4 adds relative-path support).
- **Table encryption** protects confidentiality/integrity of `data`,
  `delete`, `manifest`, and `manifest list` files at rest — but explicitly
  **not** `metadata.json` (which holds no row data or stats).
- Encryption requires two things: a catalog-level **KMS** configuration
  (`encryption.kms-type` for AWS/Azure/GCP, or `encryption.kms-impl` for a
  custom `KeyManagementClient`) and a table property
  `encryption.key-id` naming the table's master key.
  Currently supported for **Hive** and **REST** catalogs with **Parquet**
  and **Avro** data.
- Internally, Iceberg uses **envelope encryption**: per-file data keys are
  generated per write, wrapped by a rotating **key encryption key (KEK)**,
  which is itself wrapped by the table's master key via the KMS.

# FileIO — Why It Exists

| Without an abstraction | With FileIO |
|---|---|
| Iceberg core would need storage-specific code for every backend | One interface (read/write/seek); backend-specific implementations plug in |
| Hard to add new storage backends | New backend = new FileIO implementation, no core changes |
| Coupled to file system semantics (rename, listing) | Only needs in-place write, seekable read, delete — works on any object store |

Iceberg ships FileIO implementations for:

- Amazon S3
- Google Cloud Storage
- Azure / general Object Service Storage (including plain HTTPS)
- Dell Enterprise Cloud Storage (ECS)
- Hadoop (adapts any Hadoop-compatible `FileSystem`)

# Encryption — Setup

Two required configuration points:

| Config | Level | Purpose |
|---|---|---|
| `encryption.kms-type` (`aws`\|`azure`\|`gcp`) or `encryption.kms-impl` (custom class) | Catalog property | Selects the KMS client. |
| `encryption.key-id` | Table property | ID of the master key (managed in the KMS) used to encrypt/decrypt the table. |

```sql
-- Catalog-level KMS config (Spark example)
spark-sql --conf spark.sql.catalog.local.encryption.kms-type=aws ...

-- Table-level master key
CREATE TABLE local.db.table (id bigint, data string) USING iceberg
TBLPROPERTIES ('encryption.key-id'='<master-key-id>');

INSERT INTO local.db.table VALUES (1, 'a'), (2, 'b'), (3, 'c');  -- auto-encrypted
SELECT * FROM local.db.table;  -- auto-decrypted
```

Verifying encryption on disk: Parquet data files start with the `PARE`
magic string (Parquet Encrypted footer mode); manifest/manifest-list files
start with `AGS1` (AES-GCM Stream v1).

# What Gets Encrypted

| File type | Encrypted? |
|---|---|
| Data files | Yes |
| Delete files | Yes |
| Manifest files | Yes |
| Manifest list files | Yes |
| `metadata.json` | **No** — contains no row data/stats |

# Catalog Security Requirements

Because `metadata.json` is unencrypted, catalogs must ensure it can't be
tampered with to defeat encryption indirectly:

1. `encryption.key-id` must not be modifiable/removable during the table's
   lifetime.
2. Catalogs must not trust `metadata.json` content blindly if it sits in
   storage vulnerable to tampering — options are: keep metadata in a
   trusted independent store, keep it in tamper-proof storage, or verify it
   with checksums held in separate trusted storage.

# Key Management Internals (Envelope Encryption)

1. A per-file encryption key + AAD prefix (unique file ID) is generated on
   **worker nodes** for each data/delete file (passed to Parquet Modular
   Encryption or Iceberg's own AES-GCM Stream mechanism for Avro).
2. The parent **manifest** stores each file's key + AAD prefix in
   `key_metadata`; the manifest itself is encrypted (AES-GCM Stream) using
   a key/AAD generated on the **driver**.
3. The parent **manifest list** stores each manifest's key/AAD/length in
   its own `key_metadata`; the manifest list is likewise AES-GCM-Stream
   encrypted.
4. The manifest list's key metadata is itself encrypted with a **key
   encryption key (KEK)**; the active KEK's ID is recorded per-snapshot in
   `key-id` (snapshot field), and the encrypted KEK is stored in the
   table metadata `encryption-keys` list.
5. The KEK itself is wrapped by the table's **master key** via the KMS
   client and stored in `encryption-keys`. KEKs are **rotated** on a
   NIST SP 800-57-compliant schedule; old KEKs are retained (not deleted)
   so historical snapshots remain decryptable.

Custom KMS integration implements
`org.apache.iceberg.encryption.KeyManagementClient`:

```java
void initialize(Map<String, String> properties);
ByteBuffer wrapKey(ByteBuffer key, String wrappingKeyId);
ByteBuffer unwrapKey(ByteBuffer wrappedKey, String wrappingKeyId);
```

# Citations

[1] [Apache Iceberg Documentation — FileIO](https://iceberg.apache.org/docs/latest/fileio)
[2] [Apache Iceberg Documentation — Encryption](https://iceberg.apache.org/docs/latest/encryption)
