#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tower_http::cors::{CorsLayer, Any};
use axum::{extract::{Path, Query}, http::StatusCode, response::{IntoResponse, Response, sse::{Sse, Event}}, routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tracing_subscriber::{fmt, EnvFilter, prelude::*};

async fn health() -> &'static str { "ok" }

#[derive(Deserialize)]
struct ListRunsParams { limit: Option<usize> }

async fn list_runs(Query(q): Query<ListRunsParams>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let limit = q.limit.unwrap_or(20);
    let runs = notebook_core::runs::list_runs(limit).map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let data: Vec<_> = runs.into_iter().map(|r| serde_json::json!({
        "id": r.id,
        "path": r.dir.to_string_lossy(),
    })).collect();
    Ok(Json(serde_json::json!({"runs": data})))
}

async fn list_cards(Path(run_id): Path<String>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let root = notebook_core::util::default_runs_root().map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let run_dir = root.join(&run_id).join("cards");
    let mut cards = vec![];
    if let Ok(rd) = std::fs::read_dir(&run_dir) {
        for entry in rd.flatten() {
            if entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                if entry.path().extension().map(|e| e=="json").unwrap_or(false) {
                    cards.push(serde_json::json!({
                        "path": entry.path().to_string_lossy(),
                        "title": entry.file_name().to_string_lossy(),
                    }));
                }
            }
        }
    }
    Ok(Json(serde_json::json!({ "cards": cards })))
}

async fn download_artifact(Path((run_id, file)): Path<(String, String)>) -> Result<Response, (StatusCode, String)> {
    let root = notebook_core::util::default_runs_root().map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let candidate = root.join(&run_id).join(&file);
    // Basic safety: ensure the artifact is inside the run dir
    let run_dir = root.join(&run_id);
    let ok = notebook_core::util::is_path_within(&run_dir, &candidate);
    if !ok || !candidate.exists() {
        return Err((StatusCode::NOT_FOUND, "not found".to_string()));
    }
    let mime = mime_guess::from_path(&candidate).first_or_text_plain();
    let bytes = tokio::fs::read(&candidate).await.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, mime.essence_str().to_string())],
        bytes
    ).into_response())
}

#[derive(Deserialize)]
struct RunJuliaBody { code: String }

async fn cmd_run_julia(Json(body): Json<RunJuliaBody>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let run = notebook_core::runs::create_new_run(None).map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let out = notebook_core::executors::julia::run_julia_cell(&run.dir, &body.code)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(Json(serde_json::json!({
        "run_id": run.id,
        "message": out.message,
        "ok": out.ok,
    })))
}

#[derive(Deserialize)]
struct RunShellBody { cmd: String, cwd: Option<String>, timeout_secs: Option<u64> }

async fn cmd_run_shell(Json(body): Json<RunShellBody>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let run = notebook_core::runs::create_new_run(None).map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let out = notebook_core::executors::shell::run_shell(&run.dir, &body.cmd, body.cwd.as_deref(), body.timeout_secs)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(Json(serde_json::json!({
        "run_id": run.id,
        "message": out.message,
        "ok": out.ok,
    })))
}

async fn sse_run_events(axum::extract::Path(_run_id): axum::extract::Path<String>) -> Sse<impl futures::Stream<Item = Result<Event, std::convert::Infallible>>> {
    use futures::StreamExt;
    use tokio_stream::wrappers::ReceiverStream;

    // TODO: wire to real core event broadcaster; for now, create a bounded channel and yield nothing until producer sends.
    let (_tx, rx) = tokio::sync::mpsc::channel::<serde_json::Value>(1024);
    let stream = ReceiverStream::new(rx).map(|ev| {
        let data = serde_json::to_string(&ev).unwrap_or("{}".to_string());
        Ok(Event::default().data(data))
    });
    Sse::new(stream)
}

#[derive(Deserialize)]
struct ConversationTurn {
    query: String,
    response: Option<String>,
}

// ARCHITECTURE: Frontend sends ONLY user input and file metadata
// Backend handles ALL business logic including:
// - Prompt construction
// - File processing strategies
// - Dataset context management
// - Instruction generation for LLM
// See docs/openai-key-flow.md for API key management
#[derive(Deserialize)]
struct SubmitQueryBody {
    // User's typed query (optional if file is provided)
    prompt: Option<String>,
    // File metadata from frontend (NOT the content)
    file_info: Option<FileInfo>,
    // Optional API key (usually fetched from server)
    api_key: Option<String>,
    // Optional conversation history
    conversation_history: Option<Vec<ConversationTurn>>,
}

#[derive(Deserialize, Debug)]
struct FileInfo {
    // File name as shown in UI
    name: String,
    // File path if available (Tauri desktop app)
    path: Option<String>,
    // Size in bytes
    size: Option<u64>,
    // MIME type
    file_type: Option<String>,
    // First 30 lines preview (ONLY for display, not processing)
    preview: Option<String>,
}

#[derive(Serialize)]
struct SubmitQueryResponse {
    run_id: String,
    ok: bool,
    response: Option<String>,
    julia_code: Option<String>,
    shell_command: Option<String>,
    execution_output: Option<String>,
    decision: Option<serde_json::Value>,
}

// ARCHITECTURE: This function handles ALL business logic
// Frontend sends raw user input, backend decides what to do
// 
// FEATURE IMPLEMENTATION GUIDE:
// 1. Add new fields to SubmitQueryBody for user input
// 2. Process and validate input here
// 3. Construct appropriate prompts here
// 4. Return structured responses
// 
// DO NOT add business logic to frontend
async fn handle_submit_query(body: SubmitQueryBody) -> anyhow::Result<SubmitQueryResponse> {
    use notebook_core::agent_loop::{agent_loop, AgentConfig};
    use notebook_core::runs::create_new_run;
    
    // Get API key from request or environment
    // See docs/openai-key-flow.md for key management strategy
    let api_key = body.api_key
        .or_else(|| std::env::var("OPENAI_API_KEY").ok())
        .ok_or_else(|| anyhow::anyhow!("No API key provided"))?;
    
    // BACKEND CONSTRUCTS THE PROMPT - NOT THE FRONTEND
    let mut full_prompt = String::new();
    
    // Handle conversation history if present
    if let Some(history) = &body.conversation_history {
        for turn in history {
            full_prompt.push_str(&format!("User: {}\n", turn.query));
            if let Some(response) = &turn.response {
                full_prompt.push_str(&format!("Assistant: {}\n", response));
            }
        }
    }
    
    // Handle file processing request
    if let Some(file_info) = &body.file_info {
        // BACKEND DECIDES HOW TO PROCESS FILES
        // This is business logic - belongs here, not in frontend
        
        if let Some(file_path) = &file_info.path {
            // Tauri desktop app - we have the exact path
            full_prompt.push_str(&format!(
                "I have a CSV file that needs to be processed and loaded into our data system.\n\n"
            ));
            full_prompt.push_str(&format!("File Location: {}\n", file_path));
            full_prompt.push_str(&format!("File Name: {}\n\n", file_info.name));
            full_prompt.push_str(
                "Please write Julia code to:\n\
                1. Load the CSV file from the given path\n\
                2. Analyze its structure and data types\n\
                3. Clean and validate the data\n\
                4. Convert it to Parquet format for efficient storage\n\
                5. Load the Parquet file into DuckDB\n\
                6. Run queries to show:\n\
                   - Total row count\n\
                   - Column names and types\n\
                   - First 5 rows\n\
                   - Basic statistics for numeric columns\n\n\
                Provide a final summary of the dataset."
            );
        } else {
            // Web browser - need to find the file
            full_prompt.push_str(&format!(
                "I have a CSV file that needs to be processed and loaded into our data system.\n\n"
            ));
            
            // Add file metadata
            full_prompt.push_str("File Information:\n");
            full_prompt.push_str(&format!("- Name: {}\n", file_info.name));
            
            if let Some(size) = file_info.size {
                let size_display = if size > 1_048_576 {
                    format!("{:.2} MB", size as f64 / 1_048_576.0)
                } else {
                    format!("{:.2} KB", size as f64 / 1024.0)
                };
                full_prompt.push_str(&format!("- Size: {}\n", size_display));
            }
            
            if let Some(file_type) = &file_info.file_type {
                full_prompt.push_str(&format!("- Type: {}\n", file_type));
            }
            
            // Add preview if available
            if let Some(preview) = &file_info.preview {
                full_prompt.push_str(&format!("\nFirst 30 lines of the file:\n```\n{}\n```\n\n", preview));
            }
            
            full_prompt.push_str(&format!(
                "IMPORTANT: The file \"{}\" is located somewhere on the user's system.\n\n", 
                file_info.name
            ));
            
            full_prompt.push_str(
                "Please follow these steps:\n\
                1. First, use a shell command to find the location of the file on the system. \
                   Search in common locations like Downloads, Desktop, Documents, and the home directory.\n\
                2. Once you find the file path, write Julia code to:\n\
                   - Load the CSV file from the found path\n\
                   - Analyze its structure and data types\n\
                   - Clean and validate the data\n\
                   - Convert it to Parquet format for efficient storage\n\
                   - Load the Parquet file into DuckDB\n\
                   - Run queries to show:\n\
                     * Total row count\n\
                     * Column names and types\n\
                     * First 5 rows\n\
                     * Basic statistics for numeric columns\n\n\
                Provide a final summary of the dataset."
            );
        }
    } else if let Some(user_query) = &body.prompt {
        // Regular text query from user
        full_prompt.push_str(&format!("User: {}\n", user_query));
    } else {
        return Err(anyhow::anyhow!("No query or file provided"));
    }
    
    // Create a new run
    let run = create_new_run(None)?;
    let run_id = run.id.clone();
    let run_dir = run.dir.clone();
    
    // Configure agent
    let config = AgentConfig {
        openai_api_key: api_key,
        // gpt-5 is the latest model - see README.md for current model documentation
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".to_string()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url: std::env::var("CEDAR_KEY_URL").ok(),
        app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
    };
    
    // Run agent in spawned task to avoid blocking
    let _result = tokio::task::spawn_blocking(move || {
        // Create a mini tokio runtime for the agent loop
        let rt = tokio::runtime::Runtime::new()?;
        // Use 50 turns to give the LLM plenty of chances to fix errors and complete complex tasks
        rt.block_on(agent_loop(&run_dir, &full_prompt, 50, config))
    })
    .await??;
    
    // Read the run artifacts to extract results
    let mut response_data = SubmitQueryResponse {
        run_id: run_id.clone(),
        ok: true,
        response: None,
        julia_code: None,
        shell_command: None,
        execution_output: None,
        decision: None,
    };
    
    // Check for Julia execution
    let julia_code_path = run.dir.join("cell.jl");
    if julia_code_path.exists() {
        response_data.julia_code = Some(std::fs::read_to_string(&julia_code_path)?);
    }
    
    // Check for execution outcome
    let julia_outcome_path = run.dir.join("run_julia.outcome.json");
    if julia_outcome_path.exists() {
        let outcome: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&julia_outcome_path)?)?;
        if let Some(msg) = outcome.get("message").and_then(|v| v.as_str()) {
            response_data.execution_output = Some(msg.to_string());
        }
    }
    
    // Check for shell outcome
    let shell_outcome_path = run.dir.join("shell.outcome.json");
    if shell_outcome_path.exists() {
        let outcome: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&shell_outcome_path)?)?;
        if let Some(msg) = outcome.get("message").and_then(|v| v.as_str()) {
            response_data.execution_output = Some(msg.to_string());
        }
    }
    
    // Read cards for final response
    let cards_dir = run.dir.join("cards");
    if cards_dir.exists() {
        for entry in std::fs::read_dir(&cards_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                let card_data: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&path)?)?;
                if let Some(title) = card_data.get("title").and_then(|v| v.as_str()) {
                    if title == "final" {
                        if let Some(summary) = card_data.get("summary").and_then(|v| v.as_str()) {
                            response_data.response = Some(summary.to_string());
                        }
                    }
                }
            }
        }
    }
    
    // If no final response found, use execution output
    if response_data.response.is_none() && response_data.execution_output.is_some() {
        response_data.response = response_data.execution_output.clone();
    }
    
    Ok(response_data)
}

async fn http_submit_query(
    axum::Json(body): axum::Json<SubmitQueryBody>
) -> Result<axum::Json<SubmitQueryResponse>, (axum::http::StatusCode, String)> {
    let resp = handle_submit_query(body)
        .await.map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(axum::Json(resp))
}

#[allow(dead_code)]
#[tauri::command]
async fn cmd_submit_query(body: SubmitQueryBody) -> Result<SubmitQueryResponse, String> {
    handle_submit_query(body).await.map_err(|e| e.to_string())
}

fn init_tracing() {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into());
    tracing_subscriber::registry()
        .with(fmt::layer().with_target(true))
        .with(filter)
        .init();
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();
    
    // Use the serve() function from lib.rs which has all the routes including /config/openai_key
    // See docs/openai-key-flow.md for the OpenAI key management strategy
    notebook_server::serve().await
}
