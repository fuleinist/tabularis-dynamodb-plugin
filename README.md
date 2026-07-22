# Tabularis — DynamoDB Plugin

A Tabularis driver plugin that lets Tabularis users inspect, query, and manage AWS DynamoDB tables.

This plugin follows the same architecture as the [MongoDB plugin](https://github.com/TabularisDB/tabularis-mongodb-plugin) and [Elasticsearch plugin](https://github.com/TabularisDB/tabularis-elasticsearch-plugin) — a Rust binary that communicates with Tabularis via JSON-RPC 2.0 over stdio.

---

## Status

🚧 **Under development** — part of the [Plugin Bounty Board](https://tabularis.dev/plugins/bounties#dynamodb) initiative.

---

## Architecture

### Transport

JSON-RPC 2.0 over stdin/stdout (same as MongoDB and Elasticsearch plugins). Each line is a complete JSON-RPC request; the plugin responds line-by-line.

### Crate name

```
tabularis-dynamodb-plugin
```

Uses the official [AWS SDK for Rust](https://github.com/awslabs/aws-sdk-rust) (`aws-sdk-dynamodb`) with `tokio` for async I/O, following the same pattern as the Elasticsearch plugin's worker pool architecture.

## Project Layout

```
src/
├── main.rs               # stdio loop, JSON-RPC transport, worker pool
├── rpc.rs                # Method dispatch (initialize, ping, test_connection, etc.)
├── models.rs             # ConnectionParams, shared request/response types
├── error.rs              # PluginError, ErrorCode, From impls for AWS SDK errors
├── dynamodb/             # DynamoDB client wrapper and connection pool
│   ├── mod.rs
│   ├── client.rs         # DynamoDB client creation, ping, health check
│   └── pool.rs           # Optional connection pool (for SDK config caching)
├── handlers/             # RPC method implementations
│   ├── mod.rs
│   ├── models.rs         # Query, ExecuteQueryResponse, ColumnResponse, etc.
│   ├── metadata.rs       # get_tables, get_columns, get_indexes, get_foreign_keys
│   ├── query.rs          # execute_query, test_connection, ping
│   ├── crud.rs           # insert_record, update_record, delete_record
│   └── ddl.rs            # get_create_table_sql, etc.
├── utils/
│   ├── mod.rs
│   └── extractor.rs      # Parameter extraction helpers (extract_url, extract_table, etc.)
├── bin/
│   └── test_plugin.rs    # Local REPL + integration tests
testdata/                 # DynamoDB Local seed data
ui/                       # Optional UI extension (connection form customization)
```

## Implementation Plan

### Phase 1 — Scaffold & Connection (MVP)

**Goal**: Plugin loads in Tabularis, accepts connection config, and `test_connection` succeeds.

1. **Initialize Rust project**
   - `Cargo.toml` with `aws-sdk-dynamodb`, `tokio`, `serde`, `serde_json`
   - `rust-toolchain.toml` (stable)
   - `manifest.json` — plugin descriptor (see below)
   - `justfile` — development recipes (build, dev-install, repl, lint, test, etc.)
   - `.github/workflows/release.yml` — CI/CD matrix build (linux-x64, darwin-arm64, win-x64)

2. **Stdio transport** (`src/main.rs`)
   - Async worker pool reading JSON-RPC lines from stdin (same pattern as Elasticsearch plugin)
   - Bounded request queue with backpressure
   - Writer task for stdout responses

3. **RPC dispatch** (`src/rpc.rs`)
   - `initialize` → `{ success: true }`
   - `ping` → calls `test_connection`
   - `test_connection` → creates DynamoDB client, calls `ListTables` with `Limit(1)`
   - `get_tables` → returns empty array (stub)
   - `get_columns` → returns empty array (stub)
   - `get_routines` → `[]`
   - `get_views` → `[]`
   - `get_foreign_keys` → `[]`
   - `get_indexes` → `[]` (DynamoDB indexes are returned as part of table metadata)

4. **Connection models** (`src/models.rs`)
   - `ConnectionParams` — parses `driver`, `host`, `port`, `database`, `region`, `access_key_id`, `secret_access_key`, `session_token`, `profile`, `endpoint` (for local DynamoDB)
   - AWS credential resolution chain: explicit params → profile → environment → IMDS

5. **Error handling** (`src/error.rs`)
   - `PluginError` with JSON-RPC error codes
   - `From<aws_sdk_dynamodb::Error>` impl
   - `From<SdkError>` impl

6. **manifest.json**
   - `id`: `"dynamodb"`
   - `name`: `"DynamoDB"`
   - `default_port`: `8000` (DynamoDB Local)
   - Capabilities: `schemas: true`, `views: false`, `routines: false`, `file_based: false`, `connection_string: true`, `connection_uri: true`, `identifier_quote: "\""`, `readonly: false`
   - Data types: `STRING`, `NUMBER`, `BINARY`, `BOOLEAN`, `STRING_SET`, `NUMBER_SET`, `BINARY_SET`, `LIST`, `MAP`, `NULL`
   - UI extensions for connection modal (AWS auth config)

7. **AWS Auth handling**
   - Support multiple credential sources:
     - Explicit `access_key_id` + `secret_access_key` + `region` in connection params
     - AWS profile name (`~/.aws/credentials`)
     - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`)
     - IMDS/ECS for Lambda/EC2 deployments
   - Support `endpoint` override for DynamoDB Local testing
   - Region selector: `us-east-1`, `us-west-2`, `eu-west-1`, `ap-southeast-1`, etc.

---

### Phase 2 — Metadata (Table & Column Browsing)

**Goal**: Tabularis sidebar shows DynamoDB tables with their schemas.

1. **`get_tables`** → `ListTables` → returns `[{ name: "users", schema: null, comment: null }]`
   - DynamoDB is single-region-single-account; `schema` is always `null` (no multi-schema), but we can treat the account/region as a pseudo-schema
   - Paginate through `ListTables` if > 100 tables

2. **`get_databases`** → returns `[{ name: "default" }]` — DynamoDB is schema-less in the relational sense
   - Optionally surface AWS region as a "database" concept

3. **`get_schemas`** → returns `[]` (DynamoDB has no schema concept)

4. **`get_columns`** → `DescribeTable` → maps attribute definitions to column metadata:
   ```
   { name: "id", data_type: "STRING", is_pk: true, is_nullable: false, is_auto_increment: false }
   { name: "email", data_type: "STRING", is_pk: false, is_nullable: false, is_auto_increment: false }
   ```
   - Include key schema info (HASH key, RANGE key)
   - Parse `AttributeDefinitions` from `DescribeTable` response
   - Handle complex types: `LIST`, `MAP` → shown as `JSON`

5. **`get_indexes`** → `DescribeTable` → returns global secondary indexes (GSI) and local secondary indexes (LSI):
   ```
   { name: "email-index", columns: ["email"], is_unique: false, is_primary: false }
   ```

6. **`get_foreign_keys`** → returns `[]` (DynamoDB has no FK constraints)

---

### Phase 3 — Query Execution

**Goal**: Run queries against DynamoDB from the Tabularis query editor.

1. **Query modes** (shebang-prefixed, same pattern as Elasticsearch plugin):
   - `#!partiql` (default) — Execute PartiQL statements
   - `#!scan` — Scan a table with optional filter
   - `#!query` — Query a table (requires key condition)
   - `#!get` — GetItem by primary key

2. **PartiQL execution** (`#!partiql` or plain):
   - `ExecuteStatement` — for SELECT, INSERT, UPDATE, DELETE
   - `ExecuteTransaction` — for multi-statement transactions
   - Parse results into `{ columns: [...], rows: [...], affected_rows: N }`
   - Paginate via `NextToken` for large result sets
   - Example:
     ```sql
     SELECT * FROM users WHERE id = 'abc123'
     INSERT INTO users VALUE {'id': 'abc', 'email': 'a@b.com'}
     UPDATE users SET email='new@b.com' WHERE id = 'abc'
     DELETE FROM users WHERE id = 'abc'
     ```

3. **Scan mode** (`#!scan`):
   ```
   #!scan
   TableName: users
   FilterExpression: age > :val
   ExpressionAttributeValues: {":val": {"N": "21"}}
   Limit: 100
   ```
   - Supports `FilterExpression`, `ProjectionExpression`, `Limit`, `ExclusiveStartKey`
   - Returns column/row format with pagination info

4. **Query mode** (`#!query`):
   ```
   #!query
   TableName: users
   KeyConditionExpression: id = :id
   ExpressionAttributeValues: {":id": {"S": "abc123"}}
   ```
   - Requires `KeyConditionExpression`
   - Supports `FilterExpression`, `Limit`, `IndexName` (for GSIs)

5. **GetItem** (`#!get`):
   ```
   #!get
   TableName: users
   Key: {"id": {"S": "abc123"}}
   ```

6. **Result format** — matches existing plugin conventions:
   ```json
   {
     "columns": ["id", "email", "age"],
     "rows": [["abc", "a@b.com", "30"]],
     "affected_rows": 1,
     "execution_time_ms": 42,
     "truncated": false,
     "has_more": false,
     "pagination": null
   }
   ```

7. **Safety limits**:
   - Hard cap on `Scan` segment size (e.g., 1MB or 1000 items)
   - Confirmation dialog for `DeleteTable` / `DROP TABLE`
   - Read capacity unit awareness (display `ConsumedCapacity`)

---

### Phase 4 — CRUD Operations

**Goal**: Inline cell editing in Tabularis data grid.

1. **`insert_record`** → `PutItem` with the provided data map
   - Handle condition expressions for idempotent inserts
   - Return `{ affected_rows: 1 }`

2. **`update_record`** → `UpdateItem`:
   - `pk_col` + `pk_val` identify the item
   - `col_name` + `new_val` → `UpdateExpression: SET #col = :val`
   - Return `{ affected_rows: 1 }`

3. **`delete_record`** → `DeleteItem`:
   - `pk_col` + `pk_val` identify the item
   - Return `{ affected_rows: 1 }`

---

### Phase 5 — DDL Operations

**Goal**: Generate SQL snippets for schema changes.

1. **`get_create_table_sql`** → Generate PartiQL `CREATE TABLE` statement with key schema
2. **`get_add_column_sql`** → PartiQL `ALTER TABLE ADD COLUMN` (DynamoDB supports this)
3. **`get_alter_column_sql`** → PartiQL `ALTER TABLE MODIFY` (limited support)
4. **`get_create_index_sql`** → PartiQL `CREATE INDEX` for GSI creation
5. **`drop_index`** → PartiQL `DROP INDEX`

---

### Phase 6 — Polish & Advanced

**Goal**: Production-ready, tested, documented.

1. **Local DynamoDB testing**:
   - `just run-dynamodb` — starts DynamoDB Local via Docker
   - `just seed-dynamodb` — seeds test tables and data
   - Integration tests against local DynamoDB

2. **UI extension** (`ui/`):
   - Connection form with AWS region selector, credential fields, profile picker
   - DynamoDB-specific query builder (key condition, filter expression helpers)

3. **Performance**:
   - Connection pool caching (reuse SDK config between requests)
   - Pagination tokens for large table listings
   - Concurrent request handling via worker pool

4. **Documentation**:
   - README with usage examples, installation, build instructions
   - CHANGELOG.md
   - CLAUDE.md for AI-assisted development

5. **CI/CD**:
   - GitHub Actions release workflow (same as Elasticsearch plugin)
   - Cross-platform builds (Linux, macOS, Windows)
   - `cargo test` + `cargo clippy` in CI

---

## AWS Credential Resolution

The plugin supports multiple authentication methods, resolved in order:

1. **Explicit** — `access_key_id` + `secret_access_key` + `region` in connection params
2. **Session token** — `session_token` for temporary credentials (STS)
3. **AWS profile** — `profile` field names a profile in `~/.aws/credentials`
4. **Environment** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
5. **IMDS** — EC2 instance metadata / ECS task role

For local development, `endpoint` can be set to `http://localhost:8000` (DynamoDB Local).

## manifest.json

```json
{
  "id": "dynamodb",
  "name": "DynamoDB",
  "version": "0.1.0",
  "description": "Tabularis driver plugin for AWS DynamoDB",
  "default_port": 8000,
  "executable": "tabularis-dynamodb-plugin",
  "capabilities": {
    "schemas": true,
    "views": false,
    "routines": false,
    "file_based": false,
    "connection_string": true,
    "connection_uri": true,
    "identifier_quote": "\"",
    "alter_primary_key": false,
    "readonly": false,
    "manage_tables": true
  },
  "data_types": [
    { "name": "STRING", "category": "string", "requires_length": false, "requires_precision": false },
    { "name": "NUMBER", "category": "numeric", "requires_length": false, "requires_precision": false },
    { "name": "BINARY", "category": "binary", "requires_length": false, "requires_precision": false },
    { "name": "BOOLEAN", "category": "boolean", "requires_length": false, "requires_precision": false },
    { "name": "STRING_SET", "category": "other", "requires_length": false, "requires_precision": false },
    { "name": "NUMBER_SET", "category": "other", "requires_length": false, "requires_precision": false },
    { "name": "BINARY_SET", "category": "other", "requires_length": false, "requires_precision": false },
    { "name": "LIST", "category": "json", "requires_length": false, "requires_precision": false },
    { "name": "MAP", "category": "json", "requires_length": false, "requires_precision": false },
    { "name": "NULL", "category": "other", "requires_length": false, "requires_precision": false }
  ]
}
```

## Installation

```bash
# Build and install locally
just dev-install

# Or build manually
cargo build --release
# Binary: target/release/tabularis-dynamodb-plugin
```

Copy the binary and `manifest.json` to the Tabularis plugins folder:

| OS | Path |
|----|------|
| Linux | `~/.local/share/tabularis/plugins/dynamodb/` |
| macOS | `~/Library/Application Support/tabularis/plugins/dynamodb/` |
| Windows | `%APPDATA%\debba\tabularis\data\plugins\dynamodb\` |

Restart Tabularis and pick **DynamoDB** in the connection form.

## Development

```bash
# Run DynamoDB Local
just run-dynamodb

# Seed test data
just seed-dynamodb

# Launch REPL for testing RPC handlers locally
just repl

# Build
just build

# Run tests
just test

# Lint
just lint
```

## References

- [Tabularis Plugin Guide](https://github.com/TabularisDB/tabularis/blob/main/plugins/PLUGIN_GUIDE.md)
- [MongoDB Plugin](https://github.com/TabularisDB/tabularis-mongodb-plugin) — reference for CRUD, DDL, and stdio transport
- [Elasticsearch Plugin](https://github.com/TabularisDB/tabularis-elasticsearch-plugin) — reference for query modes, connection pooling, and worker pool architecture
- [Issue #502](https://github.com/TabularisDB/tabularis/issues/502) — DynamoDB support request

## License

Apache-2.0.