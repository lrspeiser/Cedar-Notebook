# Bundled Julia Environment Documentation

## Overview
CedarAI bundles a complete Julia environment with the application to ensure consistent execution across all installations without requiring users to have Julia installed on their system.

## Architecture

### Directory Structure
```
apps/cedar-bundle/
├── resources/
│   ├── julia-wrapper.sh         # Entry point for Julia execution
│   ├── julia_env/               # Julia environment directory
│   │   ├── Project.toml         # Package manifest
│   │   ├── Manifest.toml        # Locked package versions
│   │   └── depot/               # Julia package depot
│   └── julia-1.10.5-macaarch64/ # Julia binary distribution
│       └── bin/
│           └── julia            # Julia executable
```

### Julia Executor Path Resolution

The Julia executor (`notebook_core/src/executors/julia.rs`) uses the following priority for finding Julia:

1. **Environment Variable**: Checks `JULIA_BIN` environment variable
2. **Bundled Julia** (macOS): 
   - First checks: `apps/cedar-bundle/resources/julia-wrapper.sh`
   - Then checks app bundle: `../../Resources/julia-wrapper.sh` (relative to executable)
3. **System Julia**: Falls back to system `julia` command

## What Was Broken and How We Fixed It

### Issue 1: Julia Executor Not Using Bundled Julia
**Problem**: The Julia executor was looking for Julia in the wrong location and falling back to system Julia or failing if system Julia wasn't installed.

**Root Cause**: The executor was checking for the Julia binary directly instead of using the wrapper script, and the path resolution logic wasn't accounting for the app bundle structure.

**Fix**: Updated `julia.rs` to:
1. Look for `julia-wrapper.sh` instead of the Julia binary directly
2. Check multiple possible locations for the bundled Julia
3. Add proper logging to track which Julia is being used

### Issue 2: Missing Julia Packages
**Problem**: The bundled Julia environment was missing required packages (particularly Parquet) that the AI agent needed for data processing.

**Root Cause**: The initial bundle only included a subset of packages, missing critical data processing libraries.

**Fix**: 
1. Installed missing packages directly into the bundled environment
2. Updated the bundled environment's Project.toml to include all required packages
3. The AI agent can now install additional packages on-demand if needed

### Issue 3: Package API Misuse
**Problem**: The AI agent was using incorrect API calls for installed packages (e.g., wrong Parquet write syntax).

**Root Cause**: Lack of detailed documentation in the system prompt about the correct usage of Julia packages.

**Fix**: Adding comprehensive Julia package API documentation to the system prompt (see below).

## Current Bundled Packages

The bundled Julia environment includes:
- **CSV v0.10.15**: Reading and writing CSV files
- **DataFrames v1.7.0**: Data manipulation and analysis
- **DuckDB v1.3.2**: In-process SQL database
- **HTTP v1.10.17**: HTTP client functionality
- **JSON v0.21.4**: JSON parsing and generation
- **JSON3 v1.14.3**: Alternative JSON library
- **Parquet v0.8.6**: Reading and writing Parquet files
- **Parquet2 v0.2.31**: Alternative Parquet implementation
- **Statistics**: Standard library for statistical functions

## Installing Additional Packages

If the AI agent needs additional packages, they can be installed on-demand:

```bash
apps/cedar-bundle/resources/julia-wrapper.sh -e "using Pkg; Pkg.add(\"PackageName\")"
```

The packages are installed into the bundled environment at:
`apps/cedar-bundle/resources/julia_env/`

## Wrapper Script Details

The `julia-wrapper.sh` script:
1. Sets up the Julia environment variables
2. Points to the bundled Julia depot and project
3. Executes Julia with the correct configuration

```bash
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export JULIA_DEPOT_PATH="$SCRIPT_DIR/julia_env/depot"
export JULIA_PROJECT="$SCRIPT_DIR/julia_env"
"$SCRIPT_DIR/julia-1.10.5-macaarch64/bin/julia" "$@"
```

## Testing the Bundled Environment

To verify the bundled Julia environment is working:

```bash
# Check Julia version
apps/cedar-bundle/resources/julia-wrapper.sh --version

# List installed packages
apps/cedar-bundle/resources/julia-wrapper.sh -e 'using Pkg; Pkg.status()'

# Test package loading
apps/cedar-bundle/resources/julia-wrapper.sh -e 'using CSV, DataFrames, Parquet, DuckDB; println("All packages loaded successfully")'
```

## Integration with Cedar CLI

The Cedar CLI uses the bundled Julia through the notebook executor:
1. The CLI creates a run directory for each execution
2. Julia code is written to a temporary file
3. The executor spawns Julia using the bundled environment
4. Output is captured and processed by the AI agent

## Troubleshooting

### Julia Not Found
- Check that `julia-wrapper.sh` exists and is executable
- Verify the Julia binary exists at the expected location
- Check environment variables aren't overriding the bundled Julia

### Package Loading Errors
- Ensure packages are installed in the bundled environment, not system Julia
- Check that JULIA_PROJECT points to the correct environment
- Verify depot path is correctly set

### Permission Issues
- Ensure the bundled Julia directory has read/execute permissions
- Check that the julia_env directory is writable for package installation
