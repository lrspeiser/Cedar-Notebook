# Architecture (Backend-enforced, LLM-first)

- Rust is the single source of truth for orchestration, IO, and logging. The LLM performs all planning and code generation.
- CQRS over rspc + specta; desktop/web consume generated TypeScript bindings.
- UIs only render manifest-driven specs (tables, vega-lite JSON, images). No client-side business logic or data joins.
- Storage: user data under OS app data, e.g. macOS `~/Library/Application Support/com.CedarAI.CedarAI/runs`.
- Streaming: long jobs emit RunEvent/LogLine streams over WS (web) and Tauri events (desktop).
