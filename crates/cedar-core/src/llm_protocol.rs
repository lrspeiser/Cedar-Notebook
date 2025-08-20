use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolKind {
    RunJulia,
    ShellExec,
    CollectMoreDataFromUser,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunJuliaArgs {
    pub code: String,
    #[serde(default)]
    pub env: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellArgs {
    pub cmd: String,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub timeout_secs: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoreArgs {
    #[serde(default)]
    pub prompt: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum CycleDecision {
    RunJulia { args: RunJuliaArgs },
    Shell { args: ShellArgs },
    MoreFromUser { args: MoreArgs },
    Final { user_output: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CycleInput {
    pub system_instructions: String,
    pub transcript: Vec<TranscriptItem>,
    pub tool_context: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptItem {
    pub role: String,   // "user" | "assistant" | "tool"
    pub content: String,
}

pub fn decision_json_schema() -> serde_json::Value {
    json!({
      "name": "cycle_decision",
      "schema": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "action": { "type": "string", "enum": ["run_julia","shell","more_from_user","final"] },
          "args": {
            "oneOf": [
              { "type":"object", "properties": { "code": { "type":"string" }, "env": { "type":["string","null"] } }, "required": ["code"], "additionalProperties": false },
              { "type":"object", "properties": { "cmd": { "type":"string" }, "cwd": { "type":["string","null"] }, "timeout_secs": { "type":["integer","null"], "minimum": 1, "maximum": 600 } }, "required": ["cmd"], "additionalProperties": false },
              { "type":"object", "properties": { "prompt": { "type":["string","null"] } }, "additionalProperties": false }
            ]
          },
          "user_output": { "type": ["string","null"] }
        },
        "required": ["action"]
      },
      "strict": true
    })
}

pub fn system_prompt() -> String {
    r#"
You are Cedar, an expert data/compute agent. Decide on ONE action per turn:
- run_julia: write a single Julia cell that can run without user input; include reading/writing files under the run directory; if you produce a small, user-facing preview, print it as a fenced block:
```PREVIEW_JSON
{ "summary": "...", "columns": [...], "rows": [...] }
```
If you create a table, write `result.parquet` in the working directory.
- shell: only for allowlisted, safe commands like `cargo --version`, `ls`, `git status`.
- more_from_user: ask a concise question.
- final: when you can answer, return Final with `user_output`.

Rules:
- Never output anything except a valid JSON decision.
- Prefer PREVIEW_JSON blocks for compact summaries; keep under 5KB.
- Avoid destructive shell commands. Use Julia for data work.
- Assume working directory is the sandboxed run directory.
"#.to_string()
}
