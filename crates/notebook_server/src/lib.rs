use axum::{extract::{Multipart, Path, Query}, http::StatusCode, response::{IntoResponse, Response, sse::{Sse, Event}, Html}, routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tower_http::cors::{CorsLayer, Any};
use notebook_core::duckdb_metadata::{DatasetMetadata, MetadataManager, ColumnInfo, detect_file_type, extract_sample_lines};

async fn health() -> &'static str { "ok" }

/// Serve the main web UI
/// 
/// IMPORTANT: This function serves the HTML frontend from the backend server.
/// The backend MUST serve the frontend to ensure:
/// 1. The app works when opened (no "localhost not found" errors)
/// 2. All business logic remains in the backend
/// 3. The frontend is just a presentation layer
/// 
/// See docs/ARCHITECTURE.md for full details on the Cedar architecture.
async fn serve_index() -> Html<String> {
    // Try to load the HTML file from various locations
    // The order matters - check bundle location first for production
    let html_content = 
        // Try app bundle location first (production)
        std::fs::read_to_string("/Applications/Cedar.app/Contents/Resources/web-ui/index.html")
        .or_else(|_| std::fs::read_to_string("./web-ui/index.html"))  // Development
        .or_else(|_| std::fs::read_to_string("apps/web-ui/index.html"))  // Workspace root
        .or_else(|_| {
            // Check if we're running from within an app bundle
            if let Ok(exe_path) = std::env::current_exe() {
                if exe_path.to_string_lossy().contains(".app/Contents/MacOS") {
                    let resources_path = exe_path
                        .parent() // MacOS
                        .and_then(|p| p.parent()) // Contents  
                        .map(|p| p.join("Resources/web-ui/index.html"));
                    
                    if let Some(path) = resources_path {
                        return std::fs::read_to_string(path);
                    }
                }
            }
            Err(std::io::Error::new(std::io::ErrorKind::NotFound, "HTML file not found"))
        })
        .unwrap_or_else(|_| {
            // Fallback to embedded HTML if file can't be found
            include_str!("../../../apps/web-ui/index.html").to_string()
        });
    
    Html(html_content)
}

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
    
    // Build full prompt with conversation history for the agent
    // The agent loop expects a fresh prompt each time, so we need to 
    // provide context from previous turns
    let full_prompt = if let Some(history) = &body.conversation_history {
        let mut context = String::new();
        if !history.is_empty() {
            context.push_str("Previous conversation:\n");
            for turn in history {
                context.push_str(&format!("User: {}\n", turn.query));
                if let Some(response) = &turn.response {
                    context.push_str(&format!("Assistant: {}\n\n", response));
                }
            }
            context.push_str("\nCurrent query:\n");
        }
        context.push_str(&body.prompt);
        context
    } else {
        body.prompt.clone()
    };
    
    // Create a new run
    let run = create_new_run(None)?;
    let run_id = run.id.clone();
    let run_dir = run.dir.clone();
    
    // Configure agent
    let config = AgentConfig {
        openai_api_key: api_key,
        // Default to gpt-4o-mini which is stable. Can override with OPENAI_MODEL=gpt-5 when ready
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_string()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url: std::env::var("CEDAR_KEY_URL").ok(),
        app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
    };
    
    // Clone full_prompt for debug output later
    let full_prompt_debug = full_prompt.clone();
    
    // Run agent in spawned task to avoid blocking
    let result = tokio::task::spawn_blocking(move || {
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
    
    // Use the final output from agent result if no response found in cards
    if response_data.response.is_none() {
        if let Some(ref final_output) = result.final_output {
            response_data.response = Some(final_output.clone());
        } else if response_data.execution_output.is_some() {
            response_data.response = response_data.execution_output.clone();
        }
    }
    
    // Add debug information
    let debug_mode = std::env::var("DEBUG").is_ok() || std::env::var("CEDAR_DEBUG").is_ok();
    if debug_mode {
        eprintln!("[DEBUG] Full prompt sent to agent:\n{}", full_prompt_debug);
        eprintln!("[DEBUG] Agent result: turns_used={}, final_output={:?}", 
                 result.turns_used, result.final_output);
        eprintln!("[DEBUG] Julia code: {:?}", response_data.julia_code);
        eprintln!("[DEBUG] Execution output: {:?}", response_data.execution_output);
        eprintln!("[DEBUG] Final response: {:?}", response_data.response);
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

/// Handle file upload and process metadata
async fn upload_file(mut multipart: Multipart) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    use notebook_core::agent_loop::{agent_loop, AgentConfig};
    
    // Get metadata DB path
    let root = notebook_core::util::default_runs_root()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let db_path = root.join("metadata.duckdb");
    let metadata_manager = MetadataManager::new(&db_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    let mut uploaded_datasets = Vec::new();
    
    while let Some(field) = multipart.next_field().await
        .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))? {
        
        let file_name = field.file_name()
            .unwrap_or("unknown")
            .to_string();
        
        // Read file content
        let data = field.bytes().await
            .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;
        
        // Save file to temp location
        let temp_dir = std::env::temp_dir();
        let file_path = temp_dir.join(&file_name);
        tokio::fs::write(&file_path, &data).await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        
        // Generate dataset ID
        let dataset_id = uuid::Uuid::new_v4().to_string();
        
        // Detect file type
        let file_type = detect_file_type(&file_path);
        
        // Extract sample lines
        let sample_data = extract_sample_lines(&file_path, 30)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        
        // Parse CSV headers to get column names if it's a CSV
        let column_info = if file_type == "CSV" {
            // Just get column names from first line
            if let Some(first_line) = sample_data.lines().next() {
                first_line.split(',').map(|col| {
                    ColumnInfo {
                        name: col.trim().trim_matches('"').to_string(),
                        data_type: "String".to_string(), // Will be determined by LLM/Julia
                        description: None,
                        min_value: None,
                        max_value: None,
                        avg_value: None,
                        median_value: None,
                        null_count: None,
                        distinct_count: None,
                    }
                }).collect()
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };
        
        // Prepare metadata for LLM enhancement
        let file_info = serde_json::json!({
            "file_name": file_name,
            "file_size": data.len(),
            "file_type": file_type,
            "sample_data": sample_data,
            "columns": column_info.iter().map(|col| {
                serde_json::json!({
                    "name": col.name
                })
            }).collect::<Vec<_>>(),
        });
        
        // Call LLM to generate title, description, and conversion code
        let llm_prompt = format!(
            "You are analyzing a data file that needs to be converted to Parquet format for efficient querying.\n\n\
            File Information:\n{}\n\n\
            First 30 lines of the file:\n{}\n\n\
            Please provide:\n\
            1. A UI Friendly Title That Reflects The Data (max 100 chars)\n\
            2. A UI Friendly Description That Describes The Data (max 500 chars)\n\
            3. For each column, provide a brief description of what it likely represents\n\
            4. Julia code to convert this file to Parquet format. The code should:\n\
               - Read the file from path: {}\n\
               - Handle any necessary data cleaning or type conversions\n\
               - Save as Parquet to: {}\n\n\
            Respond with a JSON object in this exact format:\n\
            {{\
              \"title\": \"...\",\
              \"description\": \"...\",\
              \"column_descriptions\": {{\"column_name\": \"description\", ...}},\
              \"julia_conversion_code\": \"using CSV, DataFrames, Parquet\\n# Your conversion code here...\"\n            }}",
            serde_json::to_string_pretty(&file_info).unwrap_or_default(),
            sample_data,
            file_path.to_string_lossy(),
            file_path.with_extension("parquet").to_string_lossy()
        );
        
        // Get API key
        let api_key = std::env::var("OPENAI_API_KEY")
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "No API key configured".to_string()))?;
        
        // Create temporary run for LLM call
        let temp_run = notebook_core::runs::create_new_run(None)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        
        let config = AgentConfig {
            openai_api_key: api_key,
            // gpt-5 is the latest model - see README.md for current model documentation
            openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".to_string()),
            openai_base: std::env::var("OPENAI_BASE").ok(),
            relay_url: std::env::var("CEDAR_KEY_URL").ok(),
            app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
        };
        
        // Call LLM to get enhanced metadata
        let llm_result = tokio::task::spawn_blocking(move || {
            let rt = tokio::runtime::Runtime::new()?;
            rt.block_on(agent_loop(&temp_run.dir, &llm_prompt, 1, config))
        })
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Task execution failed: {}", e)))?
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("LLM call failed: {}", e)))?;
        
        // Parse LLM response
        let (title, description, enhanced_columns, julia_code) = if let Some(final_output) = llm_result.final_output {
            // Try to parse JSON from the response
            // First, try to extract JSON if it's embedded in text
            let json_str = if final_output.contains("{") && final_output.contains("}") {
                // Find the JSON object boundaries
                if let Some(start) = final_output.find('{') {
                    if let Some(end) = final_output.rfind('}') {
                        &final_output[start..=end]
                    } else {
                        &final_output
                    }
                } else {
                    &final_output
                }
            } else {
                &final_output
            };
            
            match serde_json::from_str::<serde_json::Value>(json_str) {
                Ok(parsed) => {
                    let title = parsed["title"].as_str().unwrap_or(&file_name).to_string();
                    let desc = parsed["description"].as_str().unwrap_or("Uploaded dataset").to_string();
                    let julia_code = parsed["julia_conversion_code"].as_str().map(|s| s.to_string());
                    
                    // Update column descriptions
                    let mut cols = column_info.clone();
                    if let Some(col_descs) = parsed["column_descriptions"].as_object() {
                        for col in &mut cols {
                            if let Some(desc) = col_descs.get(&col.name).and_then(|v| v.as_str()) {
                                col.description = Some(desc.to_string());
                            }
                        }
                    }
                    
                    (title, desc, cols, julia_code)
                },
                Err(e) => {
                    eprintln!("Warning: Failed to parse LLM JSON response: {}. Response was: {}", e, final_output);
                    (file_name.clone(), format!("Dataset from file: {}", file_name), column_info.clone(), None)
                }
            }
        } else {
            eprintln!("Warning: LLM did not provide a final output");
            (file_name.clone(), format!("Dataset from file: {}", file_name), column_info.clone(), None)
        };
        
        // If Julia code was generated, execute it to convert the file
        if let Some(julia_code) = &julia_code {
            eprintln!("Executing Julia conversion code for file: {}", file_name);
            
            // Create a run for the conversion
            let conversion_run = notebook_core::runs::create_new_run(None)
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
            
            // Execute the Julia code
            match notebook_core::executors::julia::run_julia_cell(&conversion_run.dir, julia_code) {
                Ok(result) => {
                    eprintln!("Julia conversion result: ok={}, message={}", result.ok, result.message);
                    if !result.ok {
                        eprintln!("Warning: Julia conversion failed: {}", result.message);
                    }
                },
                Err(e) => {
                    eprintln!("Error executing Julia conversion: {}", e);
                }
            }
        }
        
        // Create metadata record (including julia_code if available)
        let metadata = DatasetMetadata {
            id: dataset_id.clone(),
            file_path: file_path.to_string_lossy().to_string(),
            file_name: file_name.clone(),
            file_size: data.len() as u64,
            file_type,
            title,
            description,
            row_count: None, // Will be populated after Julia conversion to Parquet
            column_info: enhanced_columns,
            sample_data,
            uploaded_at: chrono::Utc::now(),
        };
        
        // Store Julia code in metadata for later reference (optional field)
        // Note: This would require adding a julia_code field to DatasetMetadata struct
        
        // Store in database
        metadata_manager.store_dataset(&metadata)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        
        uploaded_datasets.push(serde_json::json!({
            "id": dataset_id,
            "file_name": file_name,
            "title": metadata.title,
            "description": metadata.description,
            "row_count": metadata.row_count,
            "column_count": metadata.column_info.len(),
        }));
    }
    
    Ok(Json(serde_json::json!({
        "success": true,
        "datasets": uploaded_datasets,
    })))
}

/// List all available datasets
async fn list_datasets() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let root = notebook_core::util::default_runs_root()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let db_path = root.join("metadata.duckdb");
    
    let metadata_manager = MetadataManager::new(&db_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    let datasets = metadata_manager.list_datasets()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    let dataset_list: Vec<_> = datasets.iter().map(|ds| {
        serde_json::json!({
            "id": ds.id,
            "title": ds.title,
            "description": ds.description,
            "file_name": ds.file_name,
            "file_type": ds.file_type,
            "file_size": ds.file_size,
            "row_count": ds.row_count,
            "column_count": ds.column_info.len(),
            "uploaded_at": ds.uploaded_at.to_rfc3339(),
        })
    }).collect();
    
    Ok(Json(serde_json::json!({
        "datasets": dataset_list,
    })))
}

/// Get details of a specific dataset
async fn get_dataset(Path(dataset_id): Path<String>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let root = notebook_core::util::default_runs_root()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let db_path = root.join("metadata.duckdb");
    
    let metadata_manager = MetadataManager::new(&db_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    let dataset = metadata_manager.get_dataset(&dataset_id)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    if let Some(ds) = dataset {
        Ok(Json(serde_json::to_value(ds).unwrap_or(serde_json::json!({}))))
    } else {
        Err((StatusCode::NOT_FOUND, "Dataset not found".to_string()))
    }
}

/// Delete a dataset
async fn delete_dataset(Path(dataset_id): Path<String>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let root = notebook_core::util::default_runs_root()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let db_path = root.join("metadata.duckdb");
    
    let metadata_manager = MetadataManager::new(&db_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    metadata_manager.delete_dataset(&dataset_id)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Dataset {} deleted", dataset_id),
    })))
}

/// Get OpenAI API key from server environment for client provisioning
/// See docs/openai-key-flow.md for the complete key management strategy
/// This endpoint allows the Cedar app to fetch the key once at startup
/// and use it for all subsequent OpenAI API calls
async fn get_openai_key() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Try to get the OpenAI API key from environment
    let api_key = std::env::var("OPENAI_API_KEY")
        .or_else(|_| std::env::var("openai_api_key"))
        .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "OpenAI API key not configured on server. Please set OPENAI_API_KEY environment variable.".to_string()))?;
    
    // Validate that it looks like a valid OpenAI key
    if !api_key.starts_with("sk-") || api_key.len() < 40 {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, "Invalid OpenAI API key format on server".to_string()));
    }
    
    // Log the request (with redacted key for security)
    let key_fingerprint = format!("{}...{}", &api_key[..6], &api_key[api_key.len()-4..]);
    eprintln!("[cedar-server] OpenAI key requested, returning key with fingerprint: {}", key_fingerprint);
    
    Ok(Json(serde_json::json!({
        "openai_api_key": api_key,
        "source": "server",
    })))
}

pub async fn serve() -> anyhow::Result<()> {
    // Get port from environment or use default
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);
    
    // Build the router with all routes
    // CRITICAL: The root route "/" MUST serve the HTML frontend
    // Without this, users get "localhost not found" errors when the app opens
    // See docs/ARCHITECTURE.md for why backend must serve frontend
    let app = Router::new()
        // Serve the main web UI at root - THIS IS REQUIRED!
        .route("/", get(serve_index))
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
        // Dataset management
        .route("/datasets/upload", axum::routing::post(upload_file))
        .route("/datasets", get(list_datasets))
        .route("/datasets/:dataset_id", get(get_dataset).delete(delete_dataset))
        // SSE events
        .route("/runs/:run_id/events", get(sse_run_events))
        // Configuration endpoints
        .route("/config/openai_key", get(get_openai_key))
        // Add CORS layer for cross-origin requests
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any)
        );
    
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    println!("✅ Cedar server running on http://localhost:{}", port);
    
    // Start the server
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    
    Ok(())
}
