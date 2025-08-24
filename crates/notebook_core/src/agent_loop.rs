// CRITICAL ARCHITECTURE PRINCIPLES:
// - ALL business logic MUST be in the backend (this code)
// - Frontend should NEVER handle API keys or make LLM calls directly  
// - API keys are fetched automatically from Render server - users don't configure anything
// - The backend fetches keys from https://cedar-notebook.onrender.com  automatically
// - This ensures security, consistency, and zero-configuration for users

use crate::llm_protocol::{CycleDecision, CycleInput, TranscriptItem, system_prompt};
use crate::executors::{julia::run_julia_cell, shell::run_shell, ToolOutcome};
use crate::cards::AssistantCard;
use crate::util::{env_flag};
// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use anyhow::{Result, Context};
use chrono::Utc;
use serde_json::json;
use std::{path::Path, fs};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};

#[derive(Debug, Clone)]
pub struct AgentConfig {
    /// OpenAI API key - automatically fetched from Render server or environment
    /// NEVER expect users to provide this - backend fetches it automatically!
    pub openai_api_key: String,
    pub openai_model: String,
    pub openai_base: Option<String>,
    /// Optional: if set, requests go to this relay instead of provider
    /// Default: https://cedar-notebook.onrender.com for production and dev
    pub relay_url: Option<String>,
    /// Optional: shared token for relay auth
    pub app_shared_token: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AgentResult {
    pub final_output: Option<String>,
    pub turns_used: usize,
}

#[tracing::instrument(skip_all, fields(run_id = %run_dir.file_name().unwrap().to_str().unwrap(), user_prompt = %user_prompt))]
pub async fn agent_loop(run_dir: &Path, user_prompt: &str, max_turns: usize, cfg: AgentConfig) -> Result<AgentResult> {
    fs::create_dir_all(run_dir)?;
    let mut transcript: Vec<TranscriptItem> = vec![TranscriptItem{ role: "user".into(), content: user_prompt.into() }];
    let mut last_tool_result: Option<serde_json::Value> = None;

    // Build simple data catalog metadata for the prompt (registered datasets, if any)
    let mut data_catalog: Vec<String> = vec![];
    let mut duckdb_datasets: Vec<String> = vec![];
    
    // Check for parquet files in registry
    if let Ok(cwd) = std::env::current_dir() {
        let reg = crate::data::registry::DatasetRegistry::default_under_repo(&cwd);
        if let Ok(rd) = std::fs::read_dir(&reg.root) {
            for e in rd.flatten() {
                if e.path().extension().map(|x| x=="parquet").unwrap_or(false) {
                    if let Some(name) = e.path().file_stem().and_then(|s| s.to_str()) {
                        data_catalog.push(name.to_string());
                    }
                }
            }
        }
    }
    
    // Check for DuckDB datasets
    if let Ok(root) = crate::util::default_runs_root() {
        let db_path = root.join("metadata.duckdb");
        if db_path.exists() {
            if let Ok(manager) = crate::duckdb_metadata::MetadataManager::new(&db_path) {
                if let Ok(datasets) = manager.list_datasets() {
                    for ds in datasets {
                        duckdb_datasets.push(format!(
                            "{} ({}): {} - {} rows, {} columns",
                            ds.title, ds.file_name, ds.description, 
                            ds.row_count.unwrap_or(0), ds.column_info.len()
                        ));
                    }
                }
            }
        }
    }

    for turn in 0..max_turns {
        let mut sys = system_prompt();
        
        // Add parquet datasets if available
        if !data_catalog.is_empty() {
            sys.push_str("\nData catalog (registered parquet tables): ");
            sys.push_str(&data_catalog.join(", "));
            sys.push_str("\n");
        }
        
        // Add DuckDB datasets if available
        if !duckdb_datasets.is_empty() {
            sys.push_str("\n=== Available Datasets in DuckDB ===\n");
            sys.push_str("You can query these datasets using DuckDB in Julia. Connect to the metadata database and query the data files:\n");
            for ds in &duckdb_datasets {
                sys.push_str(&format!("  - {}\n", ds));
            }
            sys.push_str("\nTo query these datasets, use DuckDB.jl in Julia code like:\n");
            sys.push_str("```julia\n");
            sys.push_str("using DuckDB\n");
            sys.push_str("db = DuckDB.DB()  # or connect to the metadata.duckdb\n");
            sys.push_str("# Then query CSV files directly or load from metadata\n");
            sys.push_str("result = DuckDB.query(db, \"SELECT * FROM read_csv_auto('path/to/file.csv') LIMIT 10\")\n");
            sys.push_str("```\n");
        }
        
        if data_catalog.is_empty() && duckdb_datasets.is_empty() {
            sys.push_str("\nNo registered datasets found; you may use your own knowledge to write Julia code, but state that you are doing so in user_message.\n");
        }
        let cycle_input = CycleInput {
            system_instructions: sys,
            transcript: transcript.clone(),
            tool_context: last_tool_result.clone().unwrap_or(json!({})),
        };
        
        // Debug: Show what we're sending to the LLM after tool execution
        if env_flag("CEDAR_DEBUG_CONTEXT") {
            println!("\n=== SENDING TO LLM (Turn {}) ===", turn + 1);
            println!("Transcript:");
            for item in &transcript {
                println!("  [{}]: {}", item.role, item.content);
            }
            println!("\nTool Context:");
            println!("{}", serde_json::to_string_pretty(&cycle_input.tool_context).unwrap());
            println!("=== END CONTEXT ==\n");
        }
        
        let decision = call_openai_for_decision(&cycle_input, &cfg).await
            .with_context(|| "LLM call failed")?;

        if env_flag("CEDAR_LOG_LLM_JSON") {
            println!("LLM JSON: {}", serde_json::to_string_pretty(&decision)?);
        }

        match decision {
            CycleDecision::RunJulia { args } => {
                if let Some(msg) = &args.user_message { println!("{}", msg); }
                // Handle Julia execution, capturing errors to pass back to LLM
                let out = match run_julia_cell(run_dir, &args.code) {
                    Ok(result) => result,
                    Err(e) => {
                        // Create a failed ToolOutcome with the error message
                        ToolOutcome {
                            ok: false,
                            message: format!("Julia execution failed: {}", e),
                            preview_json: None,
                            table: None,
                            stdout_tail: None,
                            stderr_tail: Some(format!("Error: {}", e)),
                        }
                    }
                };
                // Persist preview if any
                persist_tool_outcome(run_dir, "run_julia", &out)?;
                last_tool_result = Some(tool_outcome_to_json(&out));
                transcript.push(TranscriptItem{ role: "tool".into(), content: format!("run_julia -> {}", out.message) });
                continue;
            }
            CycleDecision::Shell { args } => {
                if let Some(msg) = &args.user_message { println!("{}", msg); }
                // Handle shell execution, capturing errors to pass back to LLM
                let out = match run_shell(run_dir, &args.cmd, args.cwd.as_deref(), args.timeout_secs) {
                    Ok(result) => result,
                    Err(e) => {
                        // Create a failed ToolOutcome with the error message
                        ToolOutcome {
                            ok: false,
                            message: format!("Shell command failed: {}", e),
                            preview_json: None,
                            table: None,
                            stdout_tail: None,
                            stderr_tail: Some(format!("Error: {}", e)),
                        }
                    }
                };
                persist_tool_outcome(run_dir, "shell", &out)?;
                last_tool_result = Some(tool_outcome_to_json(&out));
                transcript.push(TranscriptItem{ role: "tool".into(), content: format!("shell -> {}", out.message) });
                continue;
            }
            CycleDecision::MoreFromUser { args } => {
                let q = args.prompt.unwrap_or_else(|| "Please clarify your goal.".into());
                println!("Cedar asks: {}", q);
                // In CLI, we stop here and let user re-run agent with appended input, or we could read stdin.
                write_card(run_dir, "question", &q, json!({ "turn": turn }))?;
                return Ok(AgentResult {
                    final_output: Some(q),
                    turns_used: turn + 1,
                });
            }
            CycleDecision::Final { user_output } => {
                println!("{}", user_output);
                write_card(run_dir, "final", &user_output, json!({ "turn": turn, "tool_context": last_tool_result }))?;
                return Ok(AgentResult {
                    final_output: Some(user_output),
                    turns_used: turn + 1,
                });
            }
        }
    }
    Ok(AgentResult {
        final_output: None,
        turns_used: max_turns,
    })
}

fn persist_tool_outcome(run_dir: &Path, tool: &str, out: &ToolOutcome) -> Result<()> {
    let file = run_dir.join(format!("{}.outcome.json", tool));
    let v = tool_outcome_to_json(out);
    fs::write(file, serde_json::to_vec_pretty(&v)?)?;
    if let Some(prev) = &out.preview_json {
        fs::write(run_dir.join("preview.json"), serde_json::to_vec_pretty(prev)?)?;
    }
    Ok(())
}

fn tool_outcome_to_json(out: &ToolOutcome) -> serde_json::Value {
    json!({
        "ok": out.ok,
        "message": out.message,
        "preview_json": out.preview_json,
        "table": out.table,
        "stdout_tail": out.stdout_tail,
        "stderr_tail": out.stderr_tail,
    })
}

fn write_card(run_dir: &Path, title: &str, summary: &str, details: serde_json::Value) -> Result<()> {
    let card = AssistantCard{
        ts_utc: Utc::now(),
        run_id: run_dir.file_name().unwrap().to_string_lossy().to_string(),
        title: title.to_string(),
        summary: summary.to_string(),
        details,
        files: vec![],
    };
    let _ = card.save(&run_dir.to_path_buf())?;
    Ok(())
}

pub async fn call_openai_for_decision(input: &CycleInput, cfg: &AgentConfig) -> Result<CycleDecision> {
    // IMPORTANT: As of August 1, 2025, OpenAI has released GPT-5 with the new /v1/responses API
    // This replaces the legacy /v1/chat/completions endpoint used by GPT-4 and earlier models.
    // 
    // Critical differences that previously broke our implementation:
    // 1. DO NOT use 'max_output_tokens' - this parameter causes GPT-5 to return empty content
    // 2. DO NOT use 'temperature' - not supported by GPT-5 responses API
    // 3. DO NOT use 'messages' array format - use single 'input' string instead
    // 4. DO NOT use 'response_format' - use 'text.format.type' for JSON mode
    // 5. DO NOT use 'input_items' - the correct parameter is 'input' (single string)
    //
    // The responses API is now the standard for all new OpenAI models starting with GPT-5.
    
    // Determine base URL: prefer relay if configured
    let base = if let Some(relay) = &cfg.relay_url { relay.clone() } else { cfg.openai_base.clone().unwrap_or_else(|| "https://api.openai.com".into()) };
    
    // Always use the responses endpoint - GPT-5 is now the standard (August 2025)
    let url = format!("{}/v1/responses", base.trim_end_matches('/'));
    
    let client = reqwest::Client::new();

    // Build a compact prompt
    let mut prompt = String::new();
    prompt.push_str(&input.system_instructions);
    prompt.push_str("\n--- Transcript ---\n");
    for t in &input.transcript {
        prompt.push_str(&format!("[{}] {}\n", t.role, t.content));
    }
    prompt.push_str("\n--- Tool context ---\n");
    prompt.push_str(&input.tool_context.to_string());
    prompt.push_str("\n--- End ---\n");

    // GPT-5 Responses API (fully supported as of August 1, 2025)
    // Model: gpt-5-2025-08-07 is the current production version
    let system_msg = "Return only valid JSON for the given schema. No prose.";
    let full_input = format!("{}\n\n{}", system_msg, prompt);
    
    // GPT-5 /v1/responses request format
    // CRITICAL: These are the ONLY parameters that work correctly:
    let body = serde_json::json!({
        "model": cfg.openai_model,  // Use gpt-5-2025-08-07 or later
        "input": full_input,         // Single string input (NOT 'input_items' array)
        "text": {                    // Text generation settings
            "format": {              // JSON mode configuration
                "type": "json_object"
            }
        }
        // DO NOT ADD: max_output_tokens (breaks output)
        // DO NOT ADD: temperature (not supported)
        // DO NOT ADD: messages array (use 'input' string)
        // DO NOT ADD: response_format (use 'text.format')
        // Optional: reasoning.effort can be added if needed
    });

    let mut req = client.post(&url)
        .header(CONTENT_TYPE, "application/json")
        .json(&body);

    // If using relay, send x-app-token and do NOT send provider Authorization
    if let Some(token) = &cfg.app_shared_token {
        if cfg.relay_url.is_some() {
            req = req.header("x-app-token", token);
        } else {
            // Direct provider call: use Authorization header
            req = req.header(AUTHORIZATION, format!("Bearer {}", cfg.openai_api_key));
        }
    } else {
        // No app token configured; default to direct provider Authorization
        req = req.header(AUTHORIZATION, format!("Bearer {}", cfg.openai_api_key));
    }

    let resp = req.send().await?;
    if !resp.status().is_success() {
        let txt = resp.text().await.unwrap_or_default();
        anyhow::bail!("OpenAI error: {}", txt);
    }
    let v: serde_json::Value = resp.json().await?;

    // GPT-5 Responses API output format (as of August 1, 2025)
    // The response structure contains an 'output' array with items of different types.
    // We specifically look for 'message' type items which contain the actual response content.
    // 
    // Response structure:
    // {
    //   "output": [
    //     { "type": "reasoning", ... },  // Optional reasoning trace
    //     { "type": "message", "content": [ { "type": "text", "text": "..." } ] }
    //   ]
    // }
    //
    // NOTE: The old 'choices' array from GPT-4's chat/completions API is no longer used.
    // GPT-5 exclusively uses the 'output' array format.
    
    let mut buf = String::new();
    
    // Parse GPT-5 responses API output format
    // The API can return content in two formats:
    // 1. With type="text" and "text" field
    // 2. With type="output_text" and "text" field (current format as of Aug 2025)
    if let Some(output) = v.get("output").and_then(|x| x.as_array()) {
        for item in output {
            if let Some("message") = item.get("type").and_then(|x| x.as_str()) {
                if let Some(content_arr) = item.get("content").and_then(|x| x.as_array()) {
                    for content_item in content_arr {
                        let item_type = content_item.get("type").and_then(|x| x.as_str());
                        // Handle both "text" and "output_text" types
                        if matches!(item_type, Some("text") | Some("output_text")) {
                            if let Some(text) = content_item.get("text").and_then(|x| x.as_str()) {
                                buf.push_str(text);
                            }
                        }
                    }
                }
            }
        }
    }
    
    // No fallback to old format - GPT-5 is the standard now
    if buf.is_empty() {
        anyhow::bail!("GPT-5 returned empty content. Response: {}", serde_json::to_string_pretty(&v)?);
    }

    // Parse JSON
    let decision: CycleDecision = match serde_json::from_str(&buf) {
        Ok(d) => d,
        Err(e) => {
            // Heuristic fallback: accept simpler shapes the model might emit when not using strict schema
            if let Ok(obj) = serde_json::from_str::<serde_json::Value>(&buf) {
                if let Some(action) = obj.get("action").and_then(|x| x.as_str()) {
                    match action {
                        "more_from_user" => {
                            let prompt = obj.get("prompt")
                                .or_else(|| obj.get("question"))
                                .and_then(|x| x.as_str())
                                .map(|s| s.to_string());
                            let args = crate::llm_protocol::MoreArgs { prompt };
                            return Ok(CycleDecision::MoreFromUser { args });
                        }
                        "final" => {
                            if let Some(uo) = obj.get("user_output").and_then(|x| x.as_str()) {
                                return Ok(CycleDecision::Final { user_output: uo.to_string() });
                            }
                        }
                        _ => {}
                    }
                }
            }
            // Attempt to extract from top-level response if model already returned JSON
            if let Ok(d2) = serde_json::from_value(v.clone()) {
                d2
            } else {
                anyhow::bail!("Failed to parse model JSON: {} (raw: {})", e, buf);
            }
        }
    };
    Ok(decision)
}
