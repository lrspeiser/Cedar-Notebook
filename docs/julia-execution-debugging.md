# Julia Execution Flow and Debugging Guide

## Current Issues with Julia Code Execution Feedback

### Problem Identified
When Julia code executes but doesn't explicitly print results, the execution output may be empty even though the code ran successfully. This leads to unclear feedback to the LLM, causing it to terminate with generic responses like "Query completed."

### How the Current System Works

1. **Julia Code Generation**: The LLM generates Julia code based on the query
2. **Execution**: The code is written to `cell.jl` and executed via `julia --project`
3. **Output Capture**: Both stdout and stderr are captured
4. **Feedback Loop**: Results are sent back to the LLM as `tool_context` in the next turn
5. **Decision**: The LLM decides whether to continue, ask for clarification, or provide final output

### Current Logging Locations

- **Julia code**: `{run_dir}/cell.jl`
- **Execution outcome**: `{run_dir}/run_julia.outcome.json`
- **Stdout**: Captured in memory, included in outcome JSON
- **Stderr**: Captured in memory, included in outcome JSON
- **Debug logs**: `{run_dir}/debug.log` (when RUST_LOG is set)

## Recommended Improvements

### 1. Enhanced Julia Code Generation
Modify the LLM system prompt to always include explicit output statements:

```julia
# Instead of:
result = 2 + 2

# Generate:
result = 2 + 2
println("Result: ", result)
```

### 2. Better Error Visibility in Web UI
The web UI should display:
- The actual stdout/stderr from Julia execution
- The execution status (success/failure)
- The complete `tool_outcome` JSON that was sent back to the LLM
- The LLM's reasoning for its next decision

### 3. Implementing Better Debug Output

Add these environment variables for debugging:
```bash
export RUST_LOG=debug
export CEDAR_LOG_LLM_JSON=1  # Shows raw LLM decisions
export CEDAR_DEBUG_LLM=1      # Shows LLM content previews
```

### 4. Quick Fix for the Julia Output Issue

Update the Julia executor to automatically print the last expression if no output was generated:

```rust
// In julia.rs, after execution:
if out.is_empty() && ok {
    // Try to capture the last expression's value
    // This would require modifying the Julia code wrapper
}
```

### 5. Recommended Code Changes

#### Option A: Modify Julia Code Template
Wrap all Julia code execution in a template that ensures output:

```julia
# Wrapper template
begin
    # User code here
    {{CODE}}
end |> result -> begin
    if !isnothing(result)
        println("RESULT: ", result)
    end
end
```

#### Option B: Update System Prompt
Add to the system prompt in `llm_protocol.rs`:
```
When generating Julia code:
- Always use println() to output final results
- Include descriptive labels with outputs
- Handle potential errors with try-catch blocks
```

## Testing the Feedback Loop

To verify the Julia feedback loop is working:

1. **Enable debug logging**:
   ```bash
   export RUST_LOG=debug
   export CEDAR_LOG_LLM_JSON=1
   ```

2. **Run a test query**:
   ```bash
   cargo run --bin cedar-cli -- agent --user-prompt "Calculate 2+2 and show me the result"
   ```

3. **Check the run directory**:
   ```bash
   ls -la ~/Library/Application Support/com.CedarAI.CedarAI/runs/latest/
   cat ~/Library/Application Support/com.CedarAI.CedarAI/runs/latest/run_julia.outcome.json
   ```

4. **Verify the feedback was sent to LLM**:
   Look for "tool_context" in the debug output

## Web UI Improvements Needed

The web UI at `apps/web-ui/app-enhanced.html` should be updated to show:

1. **Execution Details Panel**:
   ```javascript
   // After line 743, add:
   if (result.execution_details) {
       addFlowStep(turnContainer, '🔍 Execution Details', 
           JSON.stringify(result.execution_details, null, 2),
           { isDebug: true });
   }
   ```

2. **Tool Context Display**:
   ```javascript
   // Show what was sent back to the LLM
   if (result.tool_context) {
       addFlowStep(turnContainer, '🔄 Feedback to LLM', 
           JSON.stringify(result.tool_context, null, 2),
           { isDebug: true });
   }
   ```

3. **Server Response Enhancement**:
   The server endpoint should return more details about the execution:
   ```rust
   // In notebook_server/src/main.rs, around line 190
   if julia_outcome_path.exists() {
       let outcome: serde_json::Value = ...;
       response_data.execution_details = Some(outcome.clone());
   }
   ```

## Summary

The core issue is that Julia code execution results ARE being captured and sent back to the LLM, but:
1. Empty stdout (when code doesn't print) leads to ambiguous feedback
2. The web UI doesn't show enough detail about what happened
3. The LLM's decision-making process after receiving execution results isn't visible

To fix this, we need:
1. Better Julia code generation that always produces output
2. Enhanced web UI debugging capabilities  
3. More detailed execution result capture and display

## Related Files to Modify

- `crates/notebook_core/src/executors/julia.rs` - Julia execution logic
- `crates/notebook_core/src/agent_loop.rs` - Main agent loop and feedback
- `crates/notebook_core/src/llm_protocol.rs` - System prompts
- `crates/notebook_server/src/main.rs` - Server API responses
- `apps/web-ui/app-enhanced.html` - Web UI display logic
