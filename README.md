# CedarCLI — End‑to‑End LLM Agent Loop for Data and Compute (Rust + Julia + DuckDB)

CedarCLI is a Rust-based agent that uses an LLM to interpret requests and decide—on every turn—whether to:
- generate and run Julia code for data/compute tasks,
- execute a safe, allowlisted shell command for OS-level actions, or
- ask the user a clarifying question.

The agent loops until it reaches a satisfactory answer or a termination condition. Along the way it persists artifacts (logs, JSON previews, Parquet datasets) and tables to DuckDB-backed Parquet so results are reproducible and inspectable. A native desktop app (`cedar‑egui`) uses the same core crate.

If you want to get running quickly, start with **Quick start**.

## Quick start
1) Copy env and set your key
```bash
cp .env.example .env
# Set: OPENAI_API_KEY (and optionally OPENAI_MODEL)
```

2) Verify your toolchain
```bash
cargo run --bin cedar-cli -- doctor
```

3) Try the agent loop (terminal chat)
```bash
cargo run --bin cedar-cli -- agent --user-prompt "Hi Cedar, please wait for a CSV upload"
```

4) Ingest a local CSV via GPT mediation
```bash
cargo run --bin cedar-cli -- ingest --path data-test/"Cars Datasets 2025.csv"
```

5) Explore recent runs/cards
```bash
# List assistant summaries and card paths
cargo run --bin cedar-cli -- cards-search --query "preview" --limit 50

# Inspect persisted runs (OS app data location by default)
cargo run --bin cedar-cli -- runs-insspect --limit 20 --details
```

> Notes
> - Use straight quotes ' and "; avoid “ ” ’ from rich text.
> - Remove any leading $ or > if copying from docs.

## How it works (agent loop overview)
The LLM is the planner and router. Each turn:
1) The system sends a transcript of prior turns plus your latest input to the model.
2) The model returns a JSON decision: an action and args, or a final `user_output` string.
3) If the action is a tool call, CedarCLI validates the args, executes the tool, persists artifacts, and pushes a compact result back into the next turn’s context. If the action is `more_from_user`, it surfaces a concise question to you.
4) The loop continues (up to 30 turns) until the model emits a final `user_output`, at which point CedarCLI writes a card and exits.

**Important files**
- `crates/cedar-core/src/agent_loop.rs` — Orchestrates the loop, validates model tool args, dispatches tools, persists “cards”, and feeds results back to the model.
- `crates/cedar-core/src/llm_protocol.rs` — Canonical tool schema and conversion between the model’s JSON and typed `CycleInput`.

**Termination conditions**
- The model emits a final `user_output` (plain text for you).
- Safety violation or hard error (e.g., disallowed shell command) with no viable next steps.
- Turn limit reached.

## Tools the model can call (run_julia, shell, more_from_user)
The agent exposes exactly three tools to the LLM for autonomous operation:
- **run_julia**
  - **Purpose:** all substantive compute/data work happens in Julia (reading CSV/Parquet, transforms, joins, plotting, DuckDB via Julia packages).
  - **Args:** `{ code: string, env?: string }`
  - **Behavior:** CedarCLI writes `cell.jl` in a fresh run directory, executes Julia inside a persistent project at `.cedar/julia_env`, captures stdout/stderr to `julia.stdout.txt` / `julia.stderr.txt`, and extracts optional `PREVIEW_JSON` fenced blocks to `preview.json`. If the Julia cell writes `result.parquet` in the run directory, CedarCLI indexes it and reports a `TablePreview` for quick UI/LLM inspection.
- **shell**
  - **Purpose:** limited OS actions like building, listing files, printing tool versions. Strongly gated to an allowlist.
  - **Args:** `{ cmd: string, cwd?: string, timeout_secs?: integer }`
  - **Behavior:** Executes via `bash -lc` on Unix or `cmd /C` on Windows. Only allowlisted prefixes are permitted (e.g., `cargo`, `git`, `python`, `julia`, `rg`, `ls`). Stdout/stderr are captured to `shell.stdout.txt` and `shell.stderr.txt` and a truncated copy is included in logs for the next LLM turn.
- **more_from_user**
  - **Purpose:** ask you a clarifying question when inputs are insufficient.
  - **Args:** `{ prompt?: string }`
  - **Behavior:** No side effects. The question is surfaced back and the loop continues once you answer.

**Validation and safety**
- Input JSON is minimally validated before dispatch; invalid or missing fields result in a structured error that the model can repair on the next turn.
- Shell commands are rejected if not on the allowlist or if `cwd` attempts to escape the designated workdir.
- Timeouts are enforced for shell; Julia runs log and return structured errors when the process fails.

## Data storage model (DuckDB + Parquet)
CedarCLI stores intermediate and final tabular results as Parquet and uses DuckDB for SQL preview/validation and export.

- **SQL executor:** `crates/cedar-core/src/executors/sql_duckdb.rs`
  - Accepts multi-statement SQL; executes DDL/DML, and exports the last row-returning statement to `run_dir/result.parquet`.
  - Produces a compact in-memory preview (rows, schema) and logs a CSV `HEAD(10)` snippet for readability.
- **Julia executor:** `crates/cedar-core/src/executors/julia.rs`
  - If your code writes `result.parquet` to the run directory, CedarCLI indexes it and emits a `TablePreview`; it also captures `PREVIEW_JSON` blocks from stdout for structured, model-friendly summaries.
- **Registry:** `crates/cedar-core/src/data/registry.rs`
  - Helpers to register datasets by logical name pointing to Parquet (or Zarr). Many ingest flows register named datasets under `data/parquet/` and then validate with SQL.

**Typical loop artifacts**
- `result.parquet` — canonical small result table for the last step
- `preview.json` — structured preview the model can reason about
- `julia.stdout.txt`, `julia.stderr.txt` — full process logs
- `shell.stdout.txt`, `shell.stderr.txt` — shell logs

You can query Parquet artifacts directly with DuckDB or Polars in follow-on steps.

## Runs, artifacts, and where data goes
Default behavior is app-like persistence to the OS application data directory, shared with the desktop app.
- macOS: `~/Library/Application Support/com.CedarAI.CedarAI/runs`
- Override for development: set `CEDAR_ALLOW_OVERRIDE=1` to honor CLI flags like `--runs-dir` and `--workdir`, which makes artifacts land under the repo (for example, `runs/{run_id}/`).

Each run directory contains at least:
- `cards/` — JSON cards with user-facing summaries and selected details
- `debug.log` — internal timestamps and tool call/result markers
- tool logs and artifacts as described above

The Runs inspector quickly summarizes recent runs and card counts:
```bash
cargo run --bin cedar-cli -- runs-inspect --limit 20 --details
```

## OpenAI configuration and key flow
There are two supported ways to provide credentials to CedarCLI for direct calls to OpenAI:

1) Local env var (simplest)
- Set OPENAI_API_KEY in your environment.
- Optional: set OPENAI_MODEL (defaults to gpt-5) and OPENAI_BASE (defaults to https://api.openai.com).

2) Server-provided key (recommended for rotation)
- Deploy the small Node relay under services/relay (Render).
- Set env in Render for that service:
  - openai_api_key: your provider key
  - APP_SHARED_TOKEN: long random value (shared with client)
- The relay exposes GET /v1/key, which returns { openai_api_key: "..." } when x-app-token matches.
- On the client machine, set:
  - CEDAR_KEY_URL=https://<your-service>.onrender.com/v1/key
  - APP_SHARED_TOKEN=<same as server>
  - (Optional) CEDAR_REFRESH_KEY=1 to force re-fetch on next run
- CedarCLI will fetch the key once, store it in the system keychain (fallback to ~/.config/cedar-cli/.env), then call OpenAI directly.

Notes
- The OpenAI API call uses the Responses API with text.format.type = json_object so the model returns a single JSON object decision.
- We do not route LLM calls through the server; the server is only used for key distribution.
- For troubleshooting and example commands, see Quick start.

## Prerequisites and environment
- Rust (stable toolchain)
- Julia 1.10+
- Python 3.x (used by some flows; the autonomous tool exposure is Julia + shell + more_from_user)
- DuckDB (linked via crate; separate install not typically required)
- **Environment variables**
  - `OPENAI_API_KEY` — required for live LLM calls
  - `OPENAI_MODEL` — optional (defaults to `gpt-5`)
  - `CEDAR_ALLOW_OVERRIDE=1` — opt-in to repo-local runs/workdir overrides for development

## Key commands (CLI)
- **Environment check**
  - `cargo run --bin cedar-cli -- doctor`
- **Agent loop (chat‑like, fully GPT-mediated)**
  - `cargo run --bin cedar-cli -- agent --user-prompt "Hello" [--file path]`
- **Ingest a local file (CSV → Parquet via Julia; register and validate via DuckDB)**
  - `cargo run --bin cedar-cli -- ingest --path uploads/sample_cars.csv`
- **Pipeline tester (step-by-step; supports --dry-run)**
  - `cargo run --bin cedar-cli -- pipeline-test --path data-test/"Cars Datasets 2025.csv"`
- **Local HTTP server (APIs; static web UI is deprecated and only for smoke tests)**
  - `cargo run --bin cedar-cli -- ui --addr 127.0.0.1:7878`
- **Search cards across runs**
  - `cargo run --bin cedar-cli -- cards-search --query "preview" --limit 50`
- **Inspect persistent runs (debugger)**
  - `cargo run --bin cedar-cli -- runs-inspect --limit 20 --details`

## Desktop app (cedar‑egui)
- Build (release):
  ```bash
  cargo build --release -p cedar-egui --manifest-path apps/cedar-egui/Cargo.toml
  ```
- Run (release):
  ```bash
  cargo run --release --manifest-path apps/cedar-egui/Cargo.toml
  ```

Note: The older Tauri/Electron wrapper is deprecated. The web UI under `webui/` is only for server smoke tests; APIs remain supported.

## Logging and observability
- Set `RUST_LOG=info` (default) or `debug` for verbose traces.
- LLM plumbing supports:
  - `CEDAR_LOG_LLM_JSON=1` — print raw LLM JSON to stdout
  - `CEDAR_DEBUG_LLM=1` — echo short LLM content previews
- Tool logs are always persisted to files in the run directory, and truncated copies are surfaced back to the model to enable self-healing without extra reads.

**Cards and assistant updates**
- Every assistant reply and important step writes a card under `runs/{run_id}/cards/*.json` so you can audit decisions post-hoc.

## Security model and guardrails
- Shell executor is allowlisted; only safe prefixes (e.g., `cargo`, `git`, `python`, `julia`, `rg`, `ls`) are executed. Destructive or unknown commands are rejected with a structured error the model can handle.
- CWD is sandboxed to the designated workdir. Attempts to escape are denied.
- Timeouts are enforced for shell; Julia failures return structured errors with captured stderr.
- Secrets should be provided via environment variables. Avoid pasting secrets directly into commands; compute them into env vars first.

## Testing
- Full suite (print test output):
  ```bash
  cargo test -- --nocapture
  ```
- Run a single test by name:
  ```bash
  cargo test web_api_basic_flows
  ```
- Run one integration file:
  ```bash
  cargo test --test server_smoke
  ```

For an ingest walkthrough without hitting live LLMs, use the pipeline tester described in `TESTING.md`.

## Git LFS and large files
This repo uses Git LFS for large assets. After clone or pull, ensure LFS objects are present:
```bash
git lfs install && git lfs pull
```

## Troubleshooting
- **Pasting commands into shells**
  - Use straight quotes ' and ". Replace “ ” ’ with straight quotes.
  - Ensure quotes are matched; avoid trailing backslashes \.
  - Remove leading `$` or `>` copied from docs.
- **Missing toolchains**
  - Run: `cargo run --bin cedar-cli -- doctor`
- **Julia package issues**
  - The executor uses a persistent project at `.cedar/julia_env` with auto-add for a small allowlist of common packages. Set `CEDAR_JULIA_AUTO_ADD=0` to disable, or `JULIA_BIN` to point to a specific binary.
- **Shell command denied**
  - The command was not on the allowlist or attempted to run outside workdir. Use `run_julia` for compute or request a permitted shell command.

## Project structure and docs
- Project structure: [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
- Testing guide: [TESTING.md](TESTING.md)
- Module design notes: see the many `*.README.md` files under `src/`
- Additional docs and ADRs: `docs/`

Contributions welcome. Please prefer verbose logging to make successes and failures observable and debuggable.
