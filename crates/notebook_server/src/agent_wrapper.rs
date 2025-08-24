use notebook_core::agent_loop::{AgentConfig, AgentResult, call_openai_for_decision};
use notebook_core::llm_protocol::{CycleDecision, CycleInput, TranscriptItem, system_prompt};
use notebook_core::executors::{julia::run_julia_cell, shell::run_shell, ToolOutcome};
use notebook_core::cards::AssistantCard;
use notebook_core::util::env_flag;

use anyhow::{Result, Context};
use chrono::Utc;
use serde_json::json;
use std::{path::Path, fs};

use crate::broadcast_event;

/// Enhanced agent loop that broadcasts events to the frontend
pub async fn agent_loop_with_events(
    run_dir: &Path, 
    user_prompt: &str, 
    max_turns: usize, 
    cfg: AgentConfig
) -> Result<AgentResult> {
    fs::create_dir_all(run_dir)?;
    let mut transcript: Vec<TranscriptItem> = vec![TranscriptItem{ role: "user".into(), content: user_prompt.into() }];
    let mut last_tool_result: Option<serde_json::Value> = None;
    
    // Broadcast initial start event
    broadcast_event("agent_start", json!({
        "run_id": run_dir.file_name().unwrap().to_str().unwrap(),
        "user_prompt": user_prompt,
        "max_turns": max_turns,
        "model": &cfg.openai_model,
    }));

    // Build simple data catalog metadata for the prompt (registered datasets, if any)
    let mut data_catalog: Vec<String> = vec![];
    let mut duckdb_datasets: Vec<String> = vec![];
    
    // Check for parquet files in registry
    if let Ok(cwd) = std::env::current_dir() {
        let reg = notebook_core::data::registry::DatasetRegistry::default_under_repo(&cwd);
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
    if let Ok(root) = notebook_core::util::default_runs_root() {
        let db_path = root.join("metadata.duckdb");
        if db_path.exists() {
            if let Ok(manager) = notebook_core::duckdb_metadata::MetadataManager::new(&db_path) {
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
        broadcast_event("turn_start", json!({
            "turn": turn + 1,
            "max_turns": max_turns,
        }));

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
            system_instructions: sys.clone(),
            transcript: transcript.clone(),
            tool_context: last_tool_result.clone().unwrap_or(json!({})),
        };
        
        // Build the full prompt that will be sent to LLM
        let mut prompt_for_llm = String::new();
        prompt_for_llm.push_str(&cycle_input.system_instructions);
        prompt_for_llm.push_str("\n--- Transcript ---\n");
        for t in &cycle_input.transcript {
            prompt_for_llm.push_str(&format!("[{}] {}\n", t.role, t.content));
        }
        prompt_for_llm.push_str("\n--- Tool context ---\n");
        prompt_for_llm.push_str(&cycle_input.tool_context.to_string());
        prompt_for_llm.push_str("\n--- End ---\n");
        
        // Broadcast the exact prompt being sent to LLM
        broadcast_event("llm_request", json!({
            "turn": turn + 1,
            "prompt": prompt_for_llm,
            "model": &cfg.openai_model,
            "transcript_length": transcript.len(),
            "has_tool_context": last_tool_result.is_some(),
        }));
        
        // Call OpenAI and get decision
        let decision_result = call_openai_for_decision(&cycle_input, &cfg).await;
        
        match decision_result {
            Ok(ref decision) => {
                // Broadcast the LLM response
                broadcast_event("llm_response", json!({
                    "turn": turn + 1,
                    "decision": serde_json::to_value(&decision).unwrap_or(json!(null)),
                    "success": true,
                }));
            },
            Err(ref e) => {
                // Broadcast LLM error
                broadcast_event("llm_error", json!({
                    "turn": turn + 1,
                    "error": e.to_string(),
                    "success": false,
                }));
                return Err(decision_result.unwrap_err());
            }
        }
        
        let decision = decision_result?;

        match decision {
            CycleDecision::RunJulia { args } => {
                if let Some(msg) = &args.user_message { 
                    println!("{}", msg);
                    broadcast_event("user_message", json!({
                        "message": msg,
                        "turn": turn + 1,
                    }));
                }
                
                // Broadcast Julia code before execution
                broadcast_event("julia_code", json!({
                    "turn": turn + 1,
                    "code": &args.code,
                }));
                
                // Handle Julia execution, capturing errors to pass back to LLM
                let out = match run_julia_cell(run_dir, &args.code) {
                    Ok(result) => {
                        broadcast_event("julia_result", json!({
                            "turn": turn + 1,
                            "success": result.ok,
                            "message": result.message,
                            "stdout": result.stdout_tail,
                            "stderr": result.stderr_tail,
                        }));
                        result
                    },
                    Err(e) => {
                        let error_msg = format!("Julia execution failed: {}", e);
                        broadcast_event("julia_error", json!({
                            "turn": turn + 1,
                            "error": &error_msg,
                        }));
                        
                        // Create a failed ToolOutcome with the error message
                        ToolOutcome {
                            ok: false,
                            message: error_msg.clone(),
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
                if let Some(msg) = &args.user_message { 
                    println!("{}", msg);
                    broadcast_event("user_message", json!({
                        "message": msg,
                        "turn": turn + 1,
                    }));
                }
                
                // Broadcast shell command before execution
                broadcast_event("shell_command", json!({
                    "turn": turn + 1,
                    "command": &args.cmd,
                    "cwd": args.cwd,
                    "timeout_secs": args.timeout_secs,
                }));
                
                // Handle shell execution, capturing errors to pass back to LLM
                let out = match run_shell(run_dir, &args.cmd, args.cwd.as_deref(), args.timeout_secs) {
                    Ok(result) => {
                        broadcast_event("shell_result", json!({
                            "turn": turn + 1,
                            "success": result.ok,
                            "message": result.message,
                            "stdout": result.stdout_tail,
                            "stderr": result.stderr_tail,
                        }));
                        result
                    },
                    Err(e) => {
                        let error_msg = format!("Shell command failed: {}", e);
                        broadcast_event("shell_error", json!({
                            "turn": turn + 1,
                            "error": &error_msg,
                        }));
                        
                        // Create a failed ToolOutcome with the error message
                        ToolOutcome {
                            ok: false,
                            message: error_msg.clone(),
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
                
                broadcast_event("agent_question", json!({
                    "turn": turn + 1,
                    "question": &q,
                }));
                
                // In CLI, we stop here and let user re-run agent with appended input, or we could read stdin.
                write_card(run_dir, "question", &q, json!({ "turn": turn }))?;
                
                broadcast_event("agent_complete", json!({
                    "turns_used": turn + 1,
                    "result": "needs_more_info",
                    "question": &q,
                }));
                
                return Ok(AgentResult {
                    final_output: Some(q),
                    turns_used: turn + 1,
                });
            }
            
            CycleDecision::Final { user_output } => {
                println!("{}", user_output);
                
                broadcast_event("agent_final", json!({
                    "turn": turn + 1,
                    "output": &user_output,
                }));
                
                write_card(run_dir, "final", &user_output, json!({ "turn": turn, "tool_context": last_tool_result }))?;
                
                broadcast_event("agent_complete", json!({
                    "turns_used": turn + 1,
                    "result": "success",
                    "output": &user_output,
                }));
                
                return Ok(AgentResult {
                    final_output: Some(user_output),
                    turns_used: turn + 1,
                });
            }
        }
    }
    
    broadcast_event("agent_complete", json!({
        "turns_used": max_turns,
        "result": "max_turns_reached",
    }));
    
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
