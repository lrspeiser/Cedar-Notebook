# Cedar Notebook: Architecture & Agent Loop Overview

## About Cedar Notebook

Cedar Notebook is a Rust-first project that wraps the core Cedar agent into a multi-modal notebook experience.  
It exposes a CLI, an HTTP/WS server, and a Tauri desktop app; all three UIs delegate **all business logic** to a common backend.  
The backend contains the long-running agent loop, executors for Julia and shell tasks, data-catalog/metadata helpers, run management, and OpenAI key management.

This document provides a complete architecture overview of the codebase and explains how the LLM agent works, how API keys are obtained securely, how file processing is handled without uploading the full file to the model, and how Parquet/DuckDB metadata is used to help the model reason about available data. Several examples illustrate the system’s behaviour.

---

## Repository Structure

The project is a Rust workspace with several crates. A simplified tree is shown below (see `PROJECT_STRUCTURE.md`):

```

.
├── Cargo.toml
├── crates
│   ├── notebook\_core    # core business logic (agent loop, executors, data catalog)
│   ├── notebook\_api     # tRPC interface exposing run\_julia, run\_shell and list\_runs
│   ├── notebook\_server  # HTTP/WS server built on axum; wraps notebook\_core
│   ├── notebook\_tauri   # thin Tauri desktop app
│   ├── cedar-cli        # command-line interface built on notebook\_core
│   └── cedar-smoke etc.
├── docs                 # design documents
├── data                 # example datasets (small)

````

Separation of concerns – the backend lives in `notebook_core` and `notebook_server` and contains thousands of lines of code, whereas the UI layers (`notebook_tauri`, CLI and web UI) are intentionally small (often under a few hundred lines). This ensures that new interfaces can be added without touching business logic.

---

## API Key Management

Cedar uses a **server-provisioned OpenAI API key model**. Keys are never stored in the client.  
When the app starts, a `KeyManager` instance (`notebook_core/src/key_manager.rs`) locates the key in the following order:

1. **Cached key** – stored in `~/.config/cedar-cli/openai_key.json`. Used if <24h old.  
2. **Server fetch** – GETs `/v1/key` or `/config/openai_key` from the Cedar server.  
   - Includes `x-app-token` if `APP_SHARED_TOKEN` is set.  
   - Validates format (`sk-...`, ≥40 chars).  
   - Caches and logs a fingerprint.  
3. **Environment fallback** – uses `OPENAI_API_KEY` env var if available.  

If no key is found, an error is returned with remediation instructions.  
The server side implements `/config/openai_key` returning `{ "openai_api_key": "...", "source": "..." }`.  
See `docs/openai-key-flow.md` for full details.

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

### Server-Sent Events (SSE) Streaming

The system now supports real-time processing updates via SSE:

* Frontend connects to `/runs/{run_id}/events` when processing starts
* Backend broadcasts status updates, tool executions, outputs
* No UI changes required - updates appear inline in result cards
* Auto-closes connections after 5 minutes to prevent hanging

### Native File Dialog (Tauri Desktop)

* Desktop app uses native OS file dialogs via Tauri
* Direct file path access - no upload needed
* Backend receives full path and processes locally
* Web fallback uses preview + file search strategy

### Improved Error Handling

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

### Desktop App (Tauri)

```bash
# Build the desktop app
cd apps/desktop
npm run tauri build

# Output: target/release/bundle/dmg/cedar-desktop_0.1.0_aarch64.dmg
```

### Backend Server

```bash
# Build optimized binary
cargo build --release --bin notebook_server

# Run with API key
OPENAI_API_KEY="sk-..." ./target/release/notebook_server
```

### Docker Deployment

```dockerfile
# Dockerfile example
FROM rust:1.70 as builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y julia
COPY --from=builder /app/target/release/notebook_server /usr/local/bin/
CMD ["notebook_server"]
```

---

## Conclusion

Cedar Notebook provides a secure and robust framework for **LLM-driven data analysis**:

* **API keys are centrally managed** - Never stored in clients
* **Backend controls all business logic** - UI is purely presentational
* **Files are processed locally** - Only previews/metadata go to the LLM
* **Parquet + DuckDB** ensure reproducibility and context
* **Real-time updates via SSE** - See processing as it happens
* **Comprehensive test coverage** - Unit, integration, and E2E tests
* **Native desktop experience** - Via Tauri with native file dialogs

The system gracefully handles everything from simple arithmetic (*2+2*) to complex data ingestion workflows, with full error recovery and retry capabilities.

