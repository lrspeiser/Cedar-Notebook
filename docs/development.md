# Development flow

- Update Rust DTOs and routes in notebook_api; regenerate bindings:
  cargo run -p notebook_api --bin export_types > bindings/desktop/bindings.ts
- UIs import from bindings/* only; no handwritten types.
- Logging: set RUST_LOG=info (or debug) and CEDAR_LOG_LLM_JSON=1 for raw JSON.
- No fallbacks: on error, return structured logs with breadcrumbs.
