# Cedar Agent Loop: Input/Output Flow Visualization

## Query: "What is 2+2?"

This shows the actual data structures and transformations at each stage.

```mermaid
graph TD
    A[User Input: "What is 2+2?"] --> B[Agent Loop Start]
    
    B --> C[Build CycleInput Turn 1]
    C --> D[Call LLM API]
    D --> E[Parse CycleDecision]
    E --> F{Decision Type?}
    
    F -->|run_julia| G[Execute Julia Code]
    G --> H[Capture ToolOutcome]
    H --> I[Update Transcript]
    I --> J[Build CycleInput Turn 2]
    
    J --> K[Call LLM API Again]
    K --> L[Parse CycleDecision]
    L --> M{Decision Type?}
    
    M -->|final| N[Output to User]
    N --> O[Save Cards & Exit]
```

## Detailed Data at Each Stage

### 1️⃣ **Initial User Input**
```plaintext
"What is 2+2? Calculate and show the result."
```

### 2️⃣ **Turn 1: First LLM Call**

**Building CycleInput:**
```rust
CycleInput {
    system_instructions: "You are Cedar, an expert data/compute agent...",
    transcript: [
        TranscriptItem { 
            role: "user", 
            content: "What is 2+2? Calculate and show the result." 
        }
    ],
    tool_context: {}
}
```

**LLM Prompt Assembled (sent to OpenAI):**
```
You are Cedar, an expert data/compute agent...
--- Transcript ---
[user] What is 2+2? Calculate and show the result.
--- Tool context ---
{}
--- End ---
```

**LLM Response (raw JSON):**
```json
{
    "action": "run_julia",
    "args": {
        "code": "result = 2 + 2\nprintln(\"2 + 2 = $result\")",
        "user_message": "I'll calculate 2+2 using Julia."
    }
}
```

### 3️⃣ **Julia Execution**

**Parsed as CycleDecision:**
```rust
CycleDecision::RunJulia {
    args: RunJuliaArgs {
        code: "result = 2 + 2\nprintln(\"2 + 2 = $result\")",
        env: None,
        user_message: Some("I'll calculate 2+2 using Julia.")
    }
}
```

**File Written:** `/runs/{uuid}/cell.jl`
```julia
result = 2 + 2
println("2 + 2 = $result")
```

**Shell Command Executed:**
```bash
julia --project /runs/{uuid}/cell.jl
```

**Raw Output Captured:**
- stdout: `"2 + 2 = 4\n"`
- stderr: `""`
- exit_code: `0`

### 4️⃣ **Tool Outcome Processing**

**ToolOutcome Structure:**
```rust
ToolOutcome {
    ok: true,
    message: "2 + 2 = 4\n",
    preview_json: None,
    table: None,
    stdout_tail: Some("2 + 2 = 4"),
    stderr_tail: None
}
```

**Persisted to:** `/runs/{uuid}/run_julia.outcome.json`
```json
{
    "ok": true,
    "message": "2 + 2 = 4\n",
    "preview_json": null,
    "table": null,
    "stdout_tail": "2 + 2 = 4",
    "stderr_tail": null
}
```

**Transcript Updated:**
```rust
transcript.push(TranscriptItem {
    role: "tool",
    content: "run_julia -> 2 + 2 = 4\n"
})
```

### 5️⃣ **Turn 2: Second LLM Call**

**Building CycleInput:**
```rust
CycleInput {
    system_instructions: "You are Cedar...",
    transcript: [
        TranscriptItem { role: "user", content: "What is 2+2?..." },
        TranscriptItem { role: "tool", content: "run_julia -> 2 + 2 = 4\n" }
    ],
    tool_context: {
        "ok": true,
        "message": "2 + 2 = 4\n",
        "stdout_tail": "2 + 2 = 4"
    }
}
```

**LLM Response:**
```json
{
    "action": "final",
    "user_output": "The calculation is complete! 2 + 2 equals 4."
}
```

### 6️⃣ **Final Processing**

**Parsed as CycleDecision:**
```rust
CycleDecision::Final {
    user_output: "The calculation is complete! 2 + 2 equals 4."
}
```

**Card Written:** `/runs/{uuid}/cards/final.json`
```json
{
    "ts_utc": "2024-08-20T23:30:00Z",
    "run_id": "{uuid}",
    "title": "final",
    "summary": "The calculation is complete! 2 + 2 equals 4.",
    "details": {
        "turn": 1,
        "tool_context": {
            "ok": true,
            "message": "2 + 2 = 4\n"
        }
    },
    "files": []
}
```

**Output to User:**
```
I'll calculate 2+2 using Julia.
The calculation is complete! 2 + 2 equals 4.
```

## Key Observations

1. **State Accumulation**: Each turn builds on previous turns through the transcript
2. **Tool Results**: Are passed both in transcript (summary) and tool_context (detailed)
3. **Decision Routing**: The `match` statement in `agent_loop` routes to different handlers
4. **File Persistence**: Every significant action creates artifacts for debugging
5. **Error Handling**: Each step has error propagation with context

## Files Created During Execution

```
/runs/{uuid}/
├── cards/
│   └── final.json          # Final decision card
├── cell.jl                 # Julia code that was executed
└── run_julia.outcome.json  # Julia execution result
```

## Code References

- **Main Loop**: `crates/notebook_core/src/agent_loop.rs:23-99`
- **Decision Handler**: `crates/notebook_core/src/agent_loop.rs:64-96`
- **LLM Call**: `crates/notebook_core/src/agent_loop.rs:135-254`
- **Julia Executor**: `crates/notebook_core/src/executors/julia.rs`
- **Protocol Types**: `crates/notebook_core/src/llm_protocol.rs`
