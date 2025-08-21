# Agent Loop Execution Trace: "What is 2+2?"

This document shows the complete flow of inputs and outputs through the Cedar agent loop when processing the query "What is 2+2? Calculate and show the result."

## Initial Setup

**User Input:**
```
"What is 2+2? Calculate and show the result."
```

**System Configuration:**
- Model: OpenAI GPT-4 (or configured model)
- Max turns: 5
- Run directory: `/runs/{uuid}/`

---

## Turn 1: LLM Decision Phase

### Input to LLM (CycleInput)

```json
{
  "system_instructions": "You are Cedar, an AI assistant that helps with data analysis and computation...",
  "transcript": [
    {
      "role": "user",
      "content": "What is 2+2? Calculate and show the result."
    }
  ],
  "tool_context": {}
}
```

### LLM Response (CycleDecision)

```json
{
  "action": "run_julia",
  "args": {
    "user_message": "I'll calculate 2+2 for you using Julia.",
    "code": "# Calculate 2 + 2\nresult = 2 + 2\nprintln(\"The result of 2 + 2 is: $result\")"
  }
}
```

### Tool Execution

**Julia Executor Input:**
- Working directory: `/runs/{uuid}/`
- Code file: `/runs/{uuid}/cell.jl`

**Julia Code Written:**
```julia
# Calculate 2 + 2
result = 2 + 2
println("The result of 2 + 2 is: $result")
```

**Execution Command:**
```bash
julia --project /runs/{uuid}/cell.jl
```

**Tool Outcome:**
```json
{
  "ok": true,
  "message": "The result of 2 + 2 is: 4\n",
  "preview_json": null,
  "table": null,
  "stdout_tail": "The result of 2 + 2 is: 4",
  "stderr_tail": null
}
```

**Persisted Files:**
- `/runs/{uuid}/run_julia.outcome.json` - Tool execution result
- `/runs/{uuid}/cell.jl` - Julia code that was executed
- `/runs/{uuid}/cards/001_julia_execution.json` - Decision card

---

## Turn 2: Final Response

### Input to LLM (CycleInput)

```json
{
  "system_instructions": "You are Cedar, an AI assistant...",
  "transcript": [
    {
      "role": "user",
      "content": "What is 2+2? Calculate and show the result."
    },
    {
      "role": "tool",
      "content": "run_julia -> The result of 2 + 2 is: 4\n"
    }
  ],
  "tool_context": {
    "ok": true,
    "message": "The result of 2 + 2 is: 4\n",
    "preview_json": null,
    "table": null,
    "stdout_tail": "The result of 2 + 2 is: 4",
    "stderr_tail": null
  }
}
```

### LLM Response (CycleDecision)

```json
{
  "action": "final",
  "user_output": "The calculation is complete! 2 + 2 equals **4**."
}
```

### Final Output to User

```
The calculation is complete! 2 + 2 equals **4**.
```

**Final Card Written:**
```json
{
  "ts_utc": "2024-08-20T23:30:00Z",
  "run_id": "{uuid}",
  "title": "final",
  "summary": "The calculation is complete! 2 + 2 equals **4**.",
  "details": {
    "turn": 1,
    "tool_context": {
      "ok": true,
      "message": "The result of 2 + 2 is: 4\n"
    }
  },
  "files": []
}
```

---

## Complete File Structure After Execution

```
/runs/{uuid}/
├── cards/
│   ├── 001_julia_execution.json
│   └── 002_final.json
├── cell.jl                    # Julia code that was executed
├── run_julia.outcome.json     # Julia execution result
└── preview.json               # (if data was generated)
```

---

## Key Points About the Loop

1. **Input Transformation**: User's natural language query is transformed into structured decisions
2. **Tool Execution**: The LLM decides to use Julia to perform the calculation
3. **Result Capture**: The tool's output is captured and fed back to the LLM
4. **Context Accumulation**: Each turn adds to the transcript, maintaining full context
5. **Decision Types**: The LLM can decide to:
   - Run Julia code (`run_julia`)
   - Run shell commands (`shell`)
   - Ask for more information (`more_from_user`)
   - Provide final answer (`final`)

## Logging and Debugging

To see this in action with real logging:

```bash
# Enable detailed logging
export RUST_LOG=debug
export CEDAR_LOG_LLM_JSON=1

# Run the agent
cedar-cli agent --user-prompt "What is 2+2?"

# Examine the run artifacts
./scripts/examine_agent_run.sh latest
```

The agent loop continues until either:
- A `final` decision is made
- The maximum number of turns is reached
- An error occurs
- The user is asked for more information (`more_from_user`)
