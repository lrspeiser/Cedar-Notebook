# Cedar Architecture (Backend-enforced, LLM-first)

## Core Principles

- Rust is the single source of truth for orchestration, IO, and logging. The LLM performs all planning and code generation.
- CQRS over rspc + specta; desktop/web consume generated TypeScript bindings.
- UIs only render manifest-driven specs (tables, vega-lite JSON, images). No client-side business logic or data joins.
- Storage: user data under OS app data, e.g. macOS `~/Library/Application Support/com.CedarAI.CedarAI/runs`.
- Streaming: long jobs emit RunEvent/LogLine streams over WS (web) and Tauri events (desktop).

## 🚨 CRITICAL: Backend Must Serve Frontend

**PROBLEM**: Without the backend serving the HTML at root (`/`), users get "localhost cannot be found" errors.

**SOLUTION**: The backend server MUST include:
```rust
// In notebook_server/src/lib.rs
let app = Router::new()
    .route("/", get(serve_index))  // ← THIS IS REQUIRED!
    // ... other routes
```

### Why This Matters

1. **App Launch Flow**:
   - Cedar app starts → Spawns backend server on localhost:8080
   - Opens browser to http://localhost:8080
   - Backend MUST serve HTML at this URL
   
2. **Common Mistake**: Removing the root route handler
   - Results in "localhost not found" errors
   - Browser can't access local HTML files from http:// URLs

3. **Correct Architecture**:
   - Backend = API server + static file server
   - Frontend = pure presentation layer
   - ALL business logic in backend

### File Locations

The `serve_index` function checks these locations in order:
1. **Production**: `/Applications/Cedar.app/Contents/Resources/web-ui/index.html`
2. **Development**: `./web-ui/index.html`
3. **Workspace**: `apps/web-ui/index.html`
4. **Fallback**: Embedded in binary via `include_str!`

### Bundle Structure

```
Cedar.app/
├── Contents/
│   ├── MacOS/
│   │   └── cedar-bundle
│   └── Resources/
│       ├── julia/
│       ├── julia_env/
│       └── web-ui/        ← Frontend files
│           └── index.html
```

## Backend Responsibilities

- **Serve frontend** at root URL
- **API endpoints** for all operations
- **Agent loop** and LLM interactions
- **Code execution** (Julia/shell)
- **Data management** (DuckDB)
- **Conversation history**

## Debugging

If "localhost not found":
1. Check backend is running: `ps aux | grep cedar`
2. Check port: `lsof -i :8080`
3. Verify root route exists in router
4. Ensure HTML is bundled
5. Set `CEDAR_DEBUG=1` for debug output
