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

## Conclusion

Cedar Notebook provides a secure and robust framework for **LLM-driven data analysis**:

* API keys are centrally managed.
* Backend controls all business logic.
* Files are processed locally, only previews/metadata go to the LLM.
* Parquet + DuckDB ensure reproducibility and context for model reasoning.

Examples like computing *2+2* or ingesting a CSV show how the agent orchestrates Julia and shell to produce reliable results.

