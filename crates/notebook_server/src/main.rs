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

#[derive(Deserialize)]
struct SubmitQueryBody {
    prompt: String,
    api_key: Option<String>,
    conversation_history: Option<Vec<ConversationTurn>>,
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

async fn handle_submit_query(body: SubmitQueryBody) -> anyhow::Result<SubmitQueryResponse> {
    use notebook_core::agent_loop::{agent_loop, AgentConfig};
    use notebook_core::runs::create_new_run;
    
    // Get API key from request or environment
    let api_key = body.api_key
        .or_else(|| std::env::var("OPENAI_API_KEY").ok())
        .ok_or_else(|| anyhow::anyhow!("No API key provided"))?;
    
    // Build full prompt with conversation history
    let mut full_prompt = String::new();
    if let Some(history) = &body.conversation_history {
        for turn in history {
            full_prompt.push_str(&format!("User: {}\n", turn.query));
            if let Some(response) = &turn.response {
                full_prompt.push_str(&format!("Assistant: {}\n", response));
            }
        }
        full_prompt.push_str(&format!("User: {}\n", body.prompt));
    } else {
        full_prompt = body.prompt.clone();
    }
    
    // Create a new run
    let run = create_new_run(None)?;
    let run_id = run.id.clone();
    let run_dir = run.dir.clone();
    
    // Configure agent
    let config = AgentConfig {
        openai_api_key: api_key,
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-4o-2024-08-06".to_string()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url: std::env::var("CEDAR_KEY_URL").ok(),
        app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
    };
    
    // Run agent in spawned task to avoid blocking
    let _result = tokio::task::spawn_blocking(move || {
        // Create a mini tokio runtime for the agent loop
        let rt = tokio::runtime::Runtime::new()?;
        rt.block_on(agent_loop(&run_dir, &full_prompt, 5, config))
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
    
    // Get port from environment or use default
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);
    
    // Build the router with all routes
    let app = Router::new()
        // Health check
        .route("/health", get(health))
        // Run management
        .route("/runs", get(list_runs))
        .route("/runs/:run_id/cards", get(list_cards))
        .route("/runs/:run_id/artifacts/:file", get(download_artifact))
        // Command execution
        .route("/commands/run_julia", axum::routing::post(cmd_run_julia))
        .route("/commands/run_shell", axum::routing::post(cmd_run_shell))
        .route("/commands/submit_query", axum::routing::post(http_submit_query))
        // SSE events
        .route("/runs/:run_id/events", get(sse_run_events))
        // Add CORS layer for cross-origin requests
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any)
        );
    
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    tracing::info!("Starting server on {}", addr);
    
    // Start the server
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    
    Ok(())
}
