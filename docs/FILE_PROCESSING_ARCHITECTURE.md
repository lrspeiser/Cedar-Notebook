# Cedar File Processing Architecture

## DO NOT MODIFY WITHOUT UNDERSTANDING THE FULL SYSTEM

This document explains the sophisticated file processing pipeline in Cedar. The system was carefully designed to leverage the agent loop for multi-turn processing with error recovery and comprehensive metadata generation.

## Core Principles

### 1. **All Logic in Backend**
- Frontend (Tauri/Web) only collects file paths or content
- Backend constructs prompts and orchestrates the agent loop
- LLMs make all decisions about how to process files

### 2. **Agent Loop for Processing**
- Files are processed through multiple agent turns
- Errors are automatically recovered
- Packages are installed as needed
- Results are validated and stored

### 3. **Comprehensive Metadata**
The system generates and stores:
- Row and column counts
- Column names and data types
- Statistical summaries (min/max/mean/median)
- Missing value counts
- Sample data (first 30 lines)
- LLM-generated title and description
- File path, size, and type

## File Processing Flow

### Step 1: File Selection
```
Tauri App → Native Dialog → Full File Path
Web App → File Upload → File Content
```

### Step 2: Backend Prompt Generation
When a file is received, the backend generates a comprehensive prompt that instructs the LLM to:

1. **Load and Analyze**
   - Auto-detect file type (CSV, Excel, JSON, Parquet)
   - Read from the exact file path
   - Handle encoding issues

2. **Generate Statistics**
   - Row and column counts
   - Data types for each column
   - Numeric statistics (min/max/mean/median/std)
   - String statistics (unique values, common values)
   - Missing value analysis

3. **Convert to Parquet**
   - Fix string type issues (String15/String31 → String)
   - Use `write_parquet()` function
   - Save as `result.parquet`

4. **Store in DuckDB**
   - Connect to metadata database
   - Create/replace table from Parquet
   - Run validation queries

5. **Generate Metadata**
   - Create PREVIEW_JSON blocks
   - Generate descriptive title
   - Provide insights and patterns

### Step 3: Agent Loop Execution
```rust
// The agent loop handles the entire workflow
agent_loop(&run_dir, &full_prompt, 50, config)
```

The agent can:
- Run Julia code (`run_julia` action)
- Execute shell commands (`shell` action)
- Ask for clarification (`more_from_user` action)
- Provide final answer (`final` action)

### Step 4: Error Recovery
The system prompt includes detailed error recovery instructions:

```
If Julia fails:
1. Check if Julia is installed
2. Install missing packages with Pkg.add()
3. Fix syntax errors and retry
4. Convert string types for Parquet compatibility
```

### Step 5: Metadata Storage
Results are stored in DuckDB with the following schema:

```sql
CREATE TABLE datasets (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size BIGINT NOT NULL,
    file_type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    row_count BIGINT,
    sample_data TEXT NOT NULL,
    uploaded_at TEXT NOT NULL
)

CREATE TABLE dataset_columns (
    dataset_id TEXT NOT NULL,
    column_name TEXT NOT NULL,
    data_type TEXT NOT NULL,
    description TEXT,
    min_value TEXT,
    max_value TEXT,
    avg_value DOUBLE,
    median_value DOUBLE,
    null_count BIGINT,
    distinct_count BIGINT
)
```

## Critical Code Sections

### Backend Prompt Generation
**File:** `crates/notebook_server/src/lib.rs`
**Function:** `handle_submit_query()`
**Lines:** 180-265

This section generates the comprehensive prompt for file processing. It includes:
- File path and preview
- Step-by-step instructions
- Error recovery guidance
- Output format requirements

### Agent Loop
**File:** `crates/notebook_core/src/agent_loop.rs`
**Function:** `agent_loop()`

The core orchestration that:
- Sends prompts to LLM
- Executes tool calls
- Handles errors
- Feeds results back for self-correction

### System Prompt
**File:** `crates/notebook_core/src/llm_protocol.rs`
**Function:** `system_prompt()`

Contains:
- Julia package API reference
- Error recovery instructions
- Output formatting rules
- File type handling patterns

## Why This Architecture?

### 1. **Resilience**
The agent loop can recover from errors automatically. If Julia isn't installed, it finds it. If packages are missing, it installs them. If code fails, it fixes and retries.

### 2. **Completeness**
By giving the LLM a comprehensive workflow, we ensure all metadata is generated. The system doesn't just read files - it analyzes, converts, stores, and validates.

### 3. **Flexibility**
The same system handles:
- Direct file paths (from Tauri)
- Uploaded content (from web)
- Different file types (CSV, Excel, JSON, Parquet)
- Various data issues (encoding, missing values, type conflicts)

### 4. **Maintainability**
All logic is in one place (backend). The frontend is thin. The LLM follows clear instructions. Changes to processing logic only require updating the prompt.

## Common Mistakes to Avoid

### ❌ DON'T: Simplify the Prompt
The detailed prompt ensures comprehensive processing. Simplifying it leads to:
- Missing metadata
- No error recovery
- Incomplete conversions
- Lost insights

### ❌ DON'T: Skip the Agent Loop
Direct Julia execution without the agent loop means:
- No error recovery
- No package installation
- No self-correction
- No validation

### ❌ DON'T: Process in Frontend
The frontend should NEVER:
- Parse files
- Generate statistics
- Make processing decisions
- Construct complex prompts

### ❌ DON'T: Bypass Metadata Storage
Always store in DuckDB because:
- It provides queryable history
- Enables dataset discovery
- Supports incremental analysis
- Maintains data lineage

## Testing the System

### Test Case 1: CSV with Special Characters
```bash
# File with String15 issues
echo "name,age,city" > test.csv
echo "João,25,São Paulo" >> test.csv
```
The system should handle encoding and convert to proper String type.

### Test Case 2: Missing Julia Package
Remove a package and run:
```julia
Pkg.rm("Parquet")
```
The system should detect the missing package and install it.

### Test Case 3: Large File
Process a file with 1M+ rows. The system should:
- Generate statistics without loading all data
- Create efficient Parquet representation
- Store summary metadata

## Debugging

### Enable Debug Output
```bash
export CEDAR_DEBUG=1
export CEDAR_LOG_LLM_JSON=1
export CEDAR_DEBUG_CONTEXT=1
```

### Check Run Artifacts
```bash
ls ~/Library/Application\ Support/com.CedarAI.CedarAI/runs/[run-id]/
```
Contains:
- `cell.jl` - Generated Julia code
- `julia.stdout.txt` - Julia output
- `run_julia.outcome.json` - Execution result
- `result.parquet` - Converted data
- `cards/` - Summary cards

### Monitor Agent Turns
The agent loop logs each turn with:
- LLM decision
- Tool execution
- Error recovery
- Final output

## Summary

This file processing system is the result of days of refinement. It leverages:
1. **Tauri** for native file access
2. **Agent loop** for resilient processing
3. **Julia** for data manipulation
4. **DuckDB** for metadata storage
5. **LLMs** for intelligent orchestration

The system is designed to handle real-world data with all its messiness, automatically recovering from errors and generating comprehensive metadata for future analysis.

**DO NOT MODIFY WITHOUT UNDERSTANDING ALL INTERACTIONS**
