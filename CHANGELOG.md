# Changelog

## [0.1.0] — 2026-07-22

### Added

- Initial plugin scaffold with Rust project structure
- JSON-RPC 2.0 over stdio transport with async worker pool (4 workers, bounded queue)
- AWS DynamoDB client wrapper with connection pool caching (30-min TTL)
- AWS credential resolution: explicit keys, profile, environment variables, IMDS
- Endpoint override for DynamoDB Local testing
- RPC method dispatch: `initialize`, `ping`, `test_connection`
- Metadata handlers: `get_tables`, `get_columns`, `get_indexes`, `get_foreign_keys`
- Query execution via PartiQL (`execute_query`) with 4 query modes: `#!partiql`, `#!scan`, `#!query`, `#!get`
- CRUD handlers: `insert_record`, `update_record`, `delete_record` (via PartiQL)
- DDL handlers: `get_create_table_sql`, `get_add_column_sql`, `get_alter_column_sql`, `get_create_index_sql`, `drop_index`
- `manifest.json` with DynamoDB-specific data types and capabilities
- Local REPL (`cargo run --bin test_plugin`) for testing RPC handlers
- 78 unit tests covering all modules
- GitHub Actions release workflow (cross-platform builds)
- `justfile` with development recipes
