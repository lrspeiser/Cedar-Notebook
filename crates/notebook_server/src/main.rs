use tauri::command;


use tower_http::cors::{CorsLayer, Any};
use axum::{extract::{Path, Query}, http::StatusCode, response::{IntoResponse, Response, sse::{Sse, Event}}, routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tracing_subscriber::{fmt, EnvFilter};
use reqwest;

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

async fn sse_run_events(Path(run_id): Path<String>) -> Sse<impl futures::Stream<Item = Result<Event, std::convert::Infallible>>> {
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
struct SubmitQueryBody { prompt: String }

#[derive(Serialize)]
struct SubmitQueryResponse { run_id: String, ok: bool, final_message: Option<String> }

#[tauri::command]
async fn cmd_submit_query(Json(body): Json<SubmitQueryBody>) -> Result<Json<SubmitQueryResponse>, (StatusCode, String)> {
    // Create run dir
    let run = notebook_core::runs::create_new_run(None).map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Resolve OpenAI key: prefer existing env; otherwise fetch via CEDAR_KEY_URL + APP_SHARED_TOKEN
    let mut openai_api_key = std::env::var("OPENAI_API_KEY").unwrap_or_default();
    if openai_api_key.is_empty() {
        let key_url = std::env::var("CEDAR_KEY_URL").map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "CEDAR_KEY_URL not set on server".to_string()))?;
        let token = std::env::var("APP_SHARED_TOKEN").map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "APP_SHARED_TOKEN not set on server".to_string()))?;
        let client = reqwest::Client::new();
        let resp = client.get(&key_url).header("x-app-token", token).send().await.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("key fetch failed: {}", e)))?;
        if !resp.status().is_success() {
            let txt = resp.text().await.unwrap_or_default();
            return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("key_fetch_error: {}", txt)));
        }
        let v: serde_json::Value = resp.json().await.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("bad key json: {}", e)))?;
        openai_api_key = v.get("openai_api_key").and_then(|x| x.as_str()).unwrap_or("").to_string();
        if openai_api_key.is_empty() { return Err((StatusCode::INTERNAL_SERVER_ERROR, "missing key in response".to_string())); }
    }

    // Build agent config
    let cfg = notebook_core::agent_loop::AgentConfig {
        openai_api_key,
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".into()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url: None,
        app_shared_token: None,
    };

    // Run the loop
    if let Err(e) = notebook_core::agent_loop::agent_loop(&run.dir, &body.prompt, 30, cfg).await {
        return Ok(Json(SubmitQueryResponse{ run_id: run.id, ok: false, final_message: Some(format!("agent error: {}", e)) }));
    }

    // Try to load final card summary if present
    let cards_dir = run.dir.join("cards");
    let mut final_message: Option<String> = None;
    if let Ok(rd) = std::fs::read_dir(&cards_dir) {
        for e in rd.flatten() {
            if e.path().extension().map(|x| x=="json").unwrap_or(false) {
                if let Ok(s) = std::fs::read_to_string(e.path()) {
                    if s.contains("\"title\": \"final\"") {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&s) {
                            final_message = v.get("summary").and_then(|x| x.as_str()).map(|s| s.to_string());
                            break;
                        }
                    }
                }
            }
        }
    }

    Ok(Json(SubmitQueryResponse{ run_id: run.id, ok: true, final_message }))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    fmt().with_env_filter(filter).init();

    let app = Router::new()
        .route("/healthz", get(health))
        .route("/runs", get(list_runs))
        .route("/runs/:run_id/cards", get(list_cards))
        .route("/commands/submit_query", axum::routing::post(cmd_submit_query))
        .route("/sse/run_events/:run_id", get(sse_run_events))
        .route("/artifacts/:run_id/:file", get(download_artifact))
        .layer(CorsLayer::new().allow_origin(Any).allow_methods(Any));


    let addr: SocketAddr = "127.0.0.1:8080".parse().unwrap();
    tracing::info!(%addr, "notebook_server listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
