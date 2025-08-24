# Cedar Notebook: Architecture & Agent Loop Overview

## 🎉 Version 1.0 Release

**Cedar Notebook v1.0** is now available with production-ready features including real-time debugging, cloud deployment, and a polished desktop experience.

## About Cedar Notebook

Cedar Notebook is a Rust-first desktop application that wraps the core Cedar agent into a native notebook experience.  
It's built with Tauri for a lightweight, secure desktop app that runs on macOS, Windows, and Linux.  
The app embeds a local backend server that contains the long-running agent loop, executors for Julia and shell tasks, data-catalog/metadata helpers, run management, and OpenAI key management.

### 🔑 Zero-Configuration API Key Management

**Users NEVER need to configure API keys!** Cedar automatically fetches OpenAI API keys from a central key server at `https://cedar-notebook.onrender.com`. This means:

- ✅ **No API key setup required** - Just run the app and it works
- ✅ **Centrally managed keys** - Update keys in one place for all users
- ✅ **Secure by default** - Keys never stored in client code or configs
- ✅ **Automatic fallback** - Gracefully handles key server outages

**For local development only**: Set `OPENAI_API_KEY` environment variable if not using the central key server.

This document provides a complete architecture overview of the codebase and explains how the LLM agent works, how API keys are obtained securely, how file processing is handled without uploading the full file to the model, and how Parquet/DuckDB metadata is used to help the model reason about available data. Several examples illustrate the system's behaviour.

---

## Repository Structure

The project is organized into a clean directory structure:

```
.
├── Cargo.toml              # Rust workspace configuration
├── README.md               # This file
├── .env.example            # Environment variable template
├── render.yaml             # Render deployment config
│
├── apps/                   # Frontend applications
│   └── desktop/            # Tauri desktop app (main UI)
│
├── crates/                 # Rust crates (core logic)
│   ├── notebook_core/      # Core business logic (agent loop, executors)
│   ├── notebook_api/       # tRPC interface
│   ├── notebook_server/    # HTTP/WS server (axum)
│   ├── notebook_tauri/     # Tauri desktop integration
│   └── cedar-cli/          # Command-line interface
│
├── data/                   # Data files
│   ├── parquet/            # Parquet data storage
│   └── samples/            # Sample CSV/Excel files
│
├── docs/                   # Documentation
│   ├── architecture/       # Architecture docs
│   ├── DATA_INGESTION_README.md
│   └── TESTING.md
│
├── scripts/                # Utility scripts
│   ├── build_*.sh          # Build scripts
│   ├── start_cedar_server.sh
│   └── ...
│
├── tests/                  # Test suite
│   ├── test_backend_unit.py
│   ├── run_all_tests.sh
│   └── ...
│
└── logs/                   # Log files (gitignored)
```

Separation of concerns – the backend lives in `notebook_core` and `notebook_server` and contains thousands of lines of code, whereas the UI layer (Tauri desktop app) is intentionally thin, serving only as a native wrapper around the embedded web view. This ensures clean architecture and maintainability.

---

## API Key Management - Fully Automatic!

### 🎯 Production Mode (Default)

**Cedar automatically fetches API keys from the central key server - NO USER CONFIGURATION NEEDED!**

When you run Cedar, the backend automatically:
1. **Checks for local keys** (for development)
2. **Fetches from Render key server** at `https://cedar-notebook.onrender.com`
3. **Caches the key** for optimal performance
4. **Handles all API calls** using the fetched key

### How It Works

The backend (`notebook_server/src/lib.rs`) manages all API keys:

```rust
// IMPORTANT: Business logic MUST be in backend. Frontend should NEVER handle API keys.
// The backend automatically fetches keys from the central server - users don't configure anything!
```

**Key Resolution Order**:
1. **Legacy request body** - For backwards compatibility only
2. **Local environment** - `OPENAI_API_KEY` (development only)
3. **🌟 Render key server** - `https://cedar-notebook.onrender.com` (PRODUCTION)

### Architecture Principles

- **NO business logic in frontend** - All LLM interactions happen in backend
- **Automatic key provisioning** - Backend fetches keys from central server
- **Zero user configuration** - It just works out of the box
- **Secure by design** - Keys never exposed to client code

### For Developers Only

If developing locally without the key server:
```bash
export OPENAI_API_KEY="your-dev-key"
cargo run --bin notebook_server
```

But in production, users just run the app - no setup needed!

### Error Handling
- Clear error messages if key server is unreachable
- Automatic retry logic for network issues  
- Debug logs show key source and fingerprint (not full key)
- Frontend shows helpful guidance for resolution

### 🚨 Startup Validation

**Cedar validates API key availability at startup** to ensure a smooth user experience:

1. **Environment Loading** - Checks multiple locations for `.env` files
2. **Backend Initialization** - Starts the embedded server
3. **API Key Validation** - Verifies that either:
   - A local `OPENAI_API_KEY` is available, OR
   - The backend can successfully fetch from the key server
4. **Error Display** - Shows a clear error message if no key is available

If the validation fails, Cedar will:
- Display a native system alert (on macOS)
- Print detailed error information to the console
- Prevent the app from starting to avoid confusing errors later

This ensures users know immediately if there's a configuration issue rather than encountering cryptic errors when trying to use the app.

See `docs/openai-key-flow.md` for implementation details.

---

## LLM Agent Loop

### High-level Cycle

The core is the async `agent_loop` in `notebook_core/src/agent_loop.rs`. For each run:

1. **Build system prompt** (`system_prompt()` in `llm_protocol.rs`).  
   - Instructs GPT-5 to pick one of: `run_julia`, `shell`, `more_from_user`, `final`.  
   - JSON only, includes error recovery + Julia usage hints.  

2. **Append dataset info**.  
   - Reads `data/parquet` + `metadata.duckdb`.  
   - Injects dataset summaries into prompt.  

3. **Send to GPT-5** using `/v1/responses`.  
   - Uses `text.format.type: json_object`.  
   - Extracts and deserialises into `CycleDecision`.  

4. **Dispatch action**:  
   - **run_julia** → writes `cell.jl`, runs Julia, captures output → `run_julia.outcome.json`.  
   - **shell** → runs allow-listed command in safe sandbox.  
   - **more_from_user** → asks a clarifying question.  
   - **final** → writes final assistant card.  

This repeats until a final answer or turn limit is reached.

### Decision Schema

Defined in `llm_protocol.rs`. Example:

```json
{
  "action": "run_julia",
  "args": {
    "code": "println(2+2)",
    "user_message": "Computing 2+2"
  }
}
````

The system enforces including a `user_message` with code/shell runs.

---

## Backend-Only Business Logic

A core principle: **no business logic in the UI**.
UI sends only user input + metadata → backend builds prompts, processes files, runs agent loop.
E.g. file uploads:

* Frontend sends name, type, size, 30-line preview (not full file).
* Backend instructs model to locate + ingest file via Julia or shell code.
  This ensures sensitive data stays local.

---

## Data Storage & Metadata

### Parquet Registry

* Outputs saved as Parquet under `data/parquet`.
* `DatasetRegistry` can register datasets by logical name.

### DuckDB Metadata Manager

* Metadata stored in `metadata.duckdb`.
* Tracks dataset info, columns, samples, stats.
* Summaries injected into prompts so model knows available tables.

### Data Ingestion Workflow

* User never writes Julia directly.
* 30-row preview sent to model.
* Model generates Julia code to ingest + convert → Parquet + DuckDB metadata.
* Retries on errors.
  Supports CSV, Excel, JSON, Parquet.
  See `DATA_INGESTION_README.md`.

---

## Example Interactions

### Simple Arithmetic

User: *“What is 2+2?”*

1. Model emits:

```json
{ "action": "run_julia", "args": { "code": "println(2+2)", "user_message": "Executing Julia to compute 2+2" } }
```

2. Executor runs Julia → outputs `4`.
3. Next turn, model emits:

```json
{ "action": "final", "user_output": "4" }
```

### Safe Shell Command

```json
{ "action": "shell", "args": { "cmd": "ls", "user_message": "Listing run directory contents" } }
```

### File Ingestion

Frontend uploads `sales.csv` → sends metadata + preview.
Backend constructs prompt; model may first `find` the file, then generate Julia to ingest → result stored in Parquet + DuckDB.

---

## Recent Enhancements

### Server-Sent Events (SSE) Streaming & Real-Time Debugging

The system now supports comprehensive real-time debugging and processing updates via SSE:

#### Production Features
* Frontend connects to `/runs/{run_id}/events` when processing starts
* Backend broadcasts status updates, tool executions, outputs
* No UI changes required - updates appear inline in result cards
* Auto-closes connections after 5 minutes to prevent hanging

#### 🆕 Debug Mode - Real-Time LLM Transparency (v1.0)
* **Live Event Stream**: Connect to `/events/live` for complete debugging visibility
* **Full LLM Transparency**: See exact prompts sent to GPT, raw responses received
* **Code Execution Tracking**: Monitor Julia code, shell commands as they execute
* **Error Debugging**: Instant visibility into errors and recovery attempts
* **Global Broadcast Channel**: Tokio-based event broadcasting for all connected clients

#### Debug Event Types
```json
// Example events streamed in real-time
{"type":"prompt_sent","content":"User query: Analyze sales data..."}
{"type":"llm_response","content":"{\"action\":\"run_julia\",\"args\":{...}}"}
{"type":"julia_code","content":"using DataFrames\ndf = DataFrame(CSV.File(\"sales.csv\"))"}
{"type":"execution_result","content":"DataFrame with 1000 rows, 5 columns"}
{"type":"error","content":"FileNotFoundError: sales.csv"}
```

#### Testing Debug Mode
```html
<!-- Simple HTML page to view live events -->
<!DOCTYPE html>
<html>
<head><title>Cedar Debug Stream</title></head>
<body>
  <div id="events"></div>
  <script>
    const evtSource = new EventSource('http://localhost:8080/events/live');
    evtSource.onmessage = (event) => {
      document.getElementById('events').innerHTML += 
        `<pre>${JSON.stringify(JSON.parse(event.data), null, 2)}</pre><hr>`;
    };
  </script>
</body>
</html>
```

### Native File Dialog

* Desktop app uses native OS file dialogs via Tauri
* Direct file path access - no upload needed
* Backend receives full path and processes locally
* Seamless integration with local file system

### Spotlight File Indexing & Search

Cedar now includes a powerful file indexing system powered by macOS Spotlight:

#### Features
* **Automatic File Discovery**: Uses Spotlight (`mdfind`) to index data files across your system
* **Instant Search**: SQLite FTS5 full-text search for sub-millisecond file lookups
* **Smart Filtering**: Automatically filters for data files (CSV, Excel, JSON, Parquet, etc.)
* **Live Updates**: Indexes refresh on-demand to catch new files
* **Fallback Support**: Falls back to Spotlight if local index is empty

#### File Types Supported
* **Tabular Data**: CSV, TSV, Excel (xlsx/xls)
* **Structured Data**: JSON, JSONL, Parquet, Arrow
* **Databases**: SQLite, DuckDB
* **Scientific**: HDF5, NetCDF, FITS
* **Geospatial**: GeoJSON, Shapefile, KML/KMZ

#### API Endpoints
```bash
# Index files using Spotlight
POST /files/index

# Search indexed files instantly
POST /files/indexed/search
{
  "query": "sales data",
  "limit": 20
}

# Get index statistics
GET /files/indexed/stats
```

#### Implementation Details
* **Storage**: SQLite database at `~/.cedar/runs/file_index.sqlite`
* **Performance**: FTS5 tokenizer for instant prefix matching
* **Metadata**: Stores path, name, size, modified time, file kind
* **Smart Ranking**: Results ranked by relevance and recency

### Improved Error Handling

* **Detailed Error Messages**: Full error text from backend displayed in UI
* **Debug Console**: Toggle-able debug log with request/response details
* **Smart Error Recovery**: Helpful suggestions for common issues (missing API key, connection problems)
* **Request Visibility**: Debug mode shows exact request payloads sent to backend
* Empty datasets on first run are normal (logged, not errors)
* File path prompts only suggest shell search if path incomplete
* Graceful degradation when endpoints unavailable

---

## Testing Infrastructure

### Test Organization

All test scripts are organized in the `tests/` directory:

```bash
tests/
├── test_backend_unit.py      # Comprehensive unit tests
├── test_frontend_backend.py  # Integration tests
├── test_e2e_with_retry.py   # End-to-end tests with LLM
├── run_all_tests.sh         # Master test runner
└── ... (20+ specialized test scripts)
```

### Running Tests

#### Quick Start
```bash
# Run all tests
cd tests
./run_all_tests.sh

# Run specific test suites
python3 test_backend_unit.py      # Backend unit tests
python3 test_frontend_backend.py  # Integration tests  
python3 test_e2e_with_retry.py    # E2E with real LLM
```

#### Backend Unit Tests

Comprehensive test coverage for all endpoints:

```python
# test_backend_unit.py examples:

class TestCedarBackend(unittest.TestCase):
    def test_01_health_check(self):
        """Test health endpoint"""
        response = requests.get(f"{self.base_url}/health")
        self.assertEqual(response.status_code, 200)
        
    def test_03_submit_query_text(self):
        """Test submitting a text query"""
        payload = {
            "prompt": "What is 2 + 2?",
            "api_key": self.api_key
        }
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        self.assertEqual(response.status_code, 200)
        
    def test_07_sse_endpoint(self):
        """Test SSE endpoint availability"""
        sse_url = f"{self.base_url}/runs/{run_id}/events"
        response = requests.get(sse_url, stream=True)
        self.assertIn("text/event-stream", 
                     response.headers.get("content-type"))
```

### Test Coverage

✅ **Unit Tests** (13 tests)
- Health check & CORS headers
- Text query submission
- File path submission (Tauri mode)
- File preview submission (web mode)
- SSE endpoint availability
- Julia/Shell execution
- Error handling scenarios
- Conversation history

✅ **Integration Tests**
- End-to-end CSV processing
- Frontend-backend communication
- File upload workflows
- Dataset management

✅ **E2E Tests** (with real LLM)
- Complete data analysis workflows
- Multi-turn conversations
- Error recovery
- Complex Julia code generation

### Test Configuration

```bash
# Environment variables
export CEDAR_SERVER_URL="http://localhost:8080"  # Server URL
export OPENAI_API_KEY="sk-..."                   # API key for E2E tests

# Start server before testing
./start_cedar_server.sh

# Run tests
cd tests
./run_all_tests.sh
```

### Sample Test Output

```
============================================
🌲 CEDAR COMPREHENSIVE TEST SUITE
============================================

✓ Server is running

1. Backend Unit Tests
✅ Testing health check...
  ✓ Health check passed
✅ Testing CORS headers...
  ✓ CORS headers present
✅ Testing text query submission...
  ✓ Query submitted, run_id: abc123
✅ Testing SSE endpoint...
  ✓ SSE endpoint available
...
✅ ALL TESTS PASSED!
```

---

## Building and Deployment

### Desktop App (Tauri) - v1.0

```bash
# Build the desktop app
cd apps/desktop
npm run build         # Build frontend
npm run tauri:build   # Build complete app

# Output: target/release/bundle/dmg/Cedar_1.0.0_aarch64.dmg
```

**🆕 Version 1.0 Features:**
- Updated Cedar branding and icons
- Native macOS app with code signing ready
- Optimized bundle size
- Production-ready DMG installer

### Backend Server (Embedded)

The backend server is automatically embedded and started by the desktop app. For development:

```bash
# Build and run backend separately for testing
cargo build --release --bin notebook_server
OPENAI_API_KEY="sk-..." ./target/release/notebook_server
```

### 🆕 Cloud Deployment - Render Platform (v1.0)

**Cedar is now deployed on Render with automatic builds and deployments!**

#### Live Production URL
```
https://cedar-notebook.onrender.com
```

#### Deployment Configuration

The project includes a complete Render deployment setup:

```yaml
# render.yaml
services:
  - type: web
    name: cedarnotebook
    runtime: docker
    dockerfilePath: ./Dockerfile
    envVars:
      - key: RUST_LOG
        value: debug
      - key: PORT
        value: 8080
```

#### Build Script for Cloud Deployment

```bash
# scripts/build_for_render.sh
#!/bin/bash
# Optimized build script for Render deployment
# - Downloads Julia runtime directly (avoids Git LFS)
# - Builds Rust server from source
# - Sets up complete environment
```

#### Git LFS Management

For cloud deployment, large files are excluded from Git:
```gitignore
# .gitignore additions for Render
*.dmg           # Desktop app bundles
julia-*.tar.gz  # Julia runtime archives
```

#### Production Server URL
**CRITICAL: The ONLY Cedar server URL is https://cedar-notebook.onrender.com**

### Docker Deployment

```dockerfile
# Dockerfile for production
FROM rust:1.82 as builder
WORKDIR /app
COPY . .
RUN cargo build --release --bin notebook_server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y curl tar
# Julia installed via build script
COPY --from=builder /app/target/release/notebook_server /usr/local/bin/
COPY scripts/build_for_render.sh /app/
RUN /app/build_for_render.sh
CMD ["notebook_server"]
```

---

## What's New in Version 1.0

### 🚀 Major Features

1. **Real-Time Debug Streaming**
   - Complete transparency into LLM interactions
   - Live event broadcasting via Tokio channels
   - Debug endpoint at `/events/live` for development

2. **Cloud Deployment Ready**
   - Deployed on Render platform
   - Automatic CI/CD pipeline
   - Optimized Docker builds
   - Git LFS management for large files

3. **Production Desktop App**
   - Version 1.0.0 with Cedar branding
   - Updated high-quality icons
   - macOS DMG installer
   - Code signing ready

4. **Enhanced Error Handling**
   - Detailed error messages with recovery suggestions
   - Debug console with request/response visibility
   - Graceful degradation for missing endpoints

5. **Improved Developer Experience**
   - Comprehensive test suite with 20+ test scripts
   - Build scripts for all platforms
   - Complete documentation

## Conclusion

Cedar Notebook v1.0 provides a production-ready, secure, and robust framework for **LLM-driven data analysis**:

* **API keys are centrally managed** - Never stored in clients
* **Backend controls all business logic** - UI is purely presentational
* **Files are processed locally** - Only previews/metadata go to the LLM
* **Parquet + DuckDB** ensure reproducibility and context
* **Real-time updates via SSE** - See processing as it happens
* **🆕 Full debugging transparency** - Watch LLM interactions in real-time
* **🆕 Cloud-ready deployment** - Deploy to Render with one command
* **Comprehensive test coverage** - Unit, integration, and E2E tests
* **Native desktop experience** - Via Tauri with native file dialogs
* **🆕 Version 1.0 stability** - Production-ready for enterprise use

The system gracefully handles everything from simple arithmetic (*2+2*) to complex data ingestion workflows, with full error recovery and retry capabilities, now with complete visibility into the AI's decision-making process.

