// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use tauri::Manager;
use tauri::menu::{Menu, MenuItemBuilder, SubmenuBuilder};
use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use notebook_core::agent_loop::{agent_loop, AgentConfig};
use notebook_core::key_manager::KeyManager;

#[derive(Debug, Serialize, Deserialize)]
struct FileInfo {
    path: String,
    name: String,
    size: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct SubmitQueryBody {
    prompt: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct SubmitQueryResponse {
    run_id: String,
    final_message: String,
}

#[tauri::command]
async fn cmd_submit_query(
    body: SubmitQueryBody,
) -> Result<SubmitQueryResponse, String> {
    
    // Use the native backend to process the query with the actual agent loop
    let query = body.prompt.clone();
    
    // Get API key directly
    let key_manager = KeyManager::new()
        .map_err(|e| format!("Failed to create key manager: {}", e))?;
    let api_key = key_manager.get_api_key().await
        .map_err(|e| format!("Failed to get API key: {}", e))?;
    
    // Create run directory
    let run_id = format!("run_{}", chrono::Utc::now().timestamp_millis());
    let runs_root = dirs::data_dir()
        .ok_or("Failed to get data directory")?
        .join("CedarAI")
        .join("runs");
    std::fs::create_dir_all(&runs_root)
        .map_err(|e| format!("Failed to create runs directory: {}", e))?;
    let run_dir = runs_root.join(&run_id);
    
    // Configure agent
    let config = AgentConfig {
        openai_api_key: api_key,
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_string()),
        openai_base: None,
        relay_url: std::env::var("CEDAR_KEY_URL").ok(),
        app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
    };
    
    // Run agent loop
    let result = agent_loop(&run_dir, &query, 10, config).await
        .map_err(|e| format!("Agent loop failed: {}", e))?;
    
    Ok(SubmitQueryResponse {
        run_id,
        final_message: result.final_output.unwrap_or_else(|| format!("Completed in {} turns", result.turns_used)),
    })
}

#[tauri::command]
async fn select_file(app_handle: tauri::AppHandle) -> Result<Option<FileInfo>, String> {
    use tauri_plugin_dialog::DialogExt;
    
    // Use native file dialog to select a file
    let file_handle = app_handle
        .dialog()
        .file()
        .add_filter("Data Files", &["csv", "xlsx", "xls", "json", "parquet"])
        .add_filter("All Files", &["*"])
        .blocking_pick_file();
    
    if let Some(file_path) = file_handle {
        let path = file_path.as_path().unwrap();
        let metadata = std::fs::metadata(&path)
            .map_err(|e| format!("Failed to read file metadata: {}", e))?;
        
        let file_name = path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        Ok(Some(FileInfo {
            path: path.to_string_lossy().to_string(),
            name: file_name,
            size: metadata.len(),
        }))
    } else {
        Ok(None)
    }
}

#[tauri::command]
async fn process_file_at_path(file_path: String) -> Result<String, String> {
    // Verify the file exists
    let path = PathBuf::from(&file_path);
    if !path.exists() {
        return Err(format!("File does not exist: {}", file_path));
    }
    
    // Get file metadata
    let metadata = std::fs::metadata(&path)
        .map_err(|e| format!("Failed to read file metadata: {}", e))?;
    
    // Read first few lines for preview
    let preview = std::fs::read_to_string(&path)
        .map(|content| {
            content.lines()
                .take(5)
                .collect::<Vec<_>>()
                .join("\n")
        })
        .unwrap_or_else(|_| "[Binary file or unreadable content]".to_string());
    
    // Pass the file path to the Julia/backend for processing
    // For now, return info about the file
    Ok(format!(
        "File: {}\nSize: {} bytes\nPreview:\n{}",
        file_path,
        metadata.len(),
        preview
    ))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  // CRITICAL: Load environment variables for backend
  // The backend will handle all API key management
  // It will use local .env or fetch from cedar-notebook.onrender.com
  load_env_config();
  
  // Validate API key availability by testing initialization
  let runtime = tokio::runtime::Runtime::new().unwrap();
  let has_key = runtime.block_on(async {
    match notebook_server::initialize_native() {
      Ok(backend) => backend.initialize_api_key().await.is_ok(),
      Err(e) => {
        eprintln!("Failed to initialize backend: {}", e);
        false
      }
    }
  });
  
  if !has_key {
    show_api_key_error();
    return;
  }
  
  // Ensure the app appears in the dock on macOS
  #[cfg(target_os = "macos")]
  {
    std::thread::spawn(|| {
      std::thread::sleep(std::time::Duration::from_millis(100));
    });
  }
  
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .invoke_handler(tauri::generate_handler![cmd_submit_query, select_file, process_file_at_path])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      
      // Create menus in setup after app handle is available
      let handle = app.handle();
      
      // Create custom menu items
      let debug_console = MenuItemBuilder::new("Open Debug Console")
        .id("debug_console")
        .build(app)?;
      let close_window = MenuItemBuilder::new("Close Window")
        .id("close")
        .build(app)?;
      let quit_app = MenuItemBuilder::new("Quit Cedar")
        .id("quit")
        .accelerator("CmdOrCtrl+Q")
        .build(app)?;
      
      // Cedar menu
      let cedar_menu = SubmenuBuilder::new(handle, "Cedar")
        .item(&debug_console)
        .separator()
        .item(&close_window)
        .item(&quit_app)
        .build()?;
      
      // Edit menu with native items
      let edit_menu = SubmenuBuilder::new(handle, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;
      
      // View menu
      let view_menu = SubmenuBuilder::new(handle, "View")
        .fullscreen()
        .build()?;
      
      // Window menu
      let window_menu = SubmenuBuilder::new(handle, "Window")
        .minimize()
        .build()?;
      
      // Build and set the app menu
      let menu = Menu::with_items(
        handle,
        &[
          &cedar_menu,
          &edit_menu,
          &view_menu,
          &window_menu,
        ],
      )?;
      
      app.set_menu(menu)?;
      
      // Ensure the window is visible and focused
      if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
      }
      
      // Set up menu event listener
      app.on_menu_event(move |_app, event| {
        match event.id().as_ref() {
          "debug_console" => {
            // Toggle debug console in the app
            if let Some(window) = _app.get_webview_window("main") {
              let _ = window.eval("window.toggleDebugConsole()");
            }
          }
          "close" => {
            if let Some(window) = _app.get_webview_window("main") {
              let _ = window.close();
            }
          }
          "quit" => {
            std::process::exit(0);
          }
          _ => {}
        }
      });
      
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

/// Load environment configuration from multiple sources
/// Priority order (highest to lowest):
/// 1. System environment variables (already set)
/// 2. .env file in app bundle resources
/// 3. .env file in user's home directory
/// 4. .env file in project root (for development)
/// 
/// IMPORTANT: This must run BEFORE any API key operations
/// See docs/openai-key-flow.md for the complete flow
fn load_env_config() {
  use std::path::PathBuf;
  
  // Try to load .env from various locations
  let env_locations = vec![
    // App bundle resources (packaged with the app)
    std::env::current_exe()
      .ok()
      .and_then(|p| p.parent().map(|p| p.join(".env"))),
    // User's home directory config
    dirs::home_dir().map(|d| d.join(".cedar/.env")),
    // Project root (for development)
    PathBuf::from(".env").canonicalize().ok(),
    // Fallback: current directory
    PathBuf::from(".env").into(),
  ];
  
  for location in env_locations.into_iter().flatten() {
    if location.exists() {
      eprintln!("[cedar] Loading environment from: {}", location.display());
      if let Ok(contents) = std::fs::read_to_string(&location) {
        for line in contents.lines() {
          // Skip comments and empty lines
          if line.trim().is_empty() || line.trim().starts_with('#') {
            continue;
          }
          
          // Parse KEY=VALUE format
          if let Some((key, value)) = line.split_once('=') {
            let key = key.trim();
            let value = value.trim().trim_matches('"').trim_matches('\'');
            
            // Only set if not already set (system env vars take precedence)
            if std::env::var(key).is_err() {
              std::env::set_var(key, value);
              
              // Log important keys (but not their values for security)
              if key == "CEDAR_KEY_URL" || key == "APP_SHARED_TOKEN" {
                eprintln!("[cedar] Set {} from config file", key);
              }
            }
          }
        }
      }
      break; // Stop after first successful load
    }
  }
  
  // Log the final configuration state (for debugging)
  if std::env::var("CEDAR_KEY_URL").is_ok() && std::env::var("APP_SHARED_TOKEN").is_ok() {
    eprintln!("[cedar] ✅ Configured to fetch API key from onrender server");
  } else if std::env::var("OPENAI_API_KEY").is_ok() {
    eprintln!("[cedar] ✅ Using local OPENAI_API_KEY");
  } else {
    eprintln!("[cedar] ⚠️  No API key configuration found. Will try to fetch at runtime.");
  }
}

/// Show an error dialog when initialization fails
fn show_initialization_error(message: &str) {
  eprintln!("\n===========================================\n");
  eprintln!("ERROR: {}", message);
  eprintln!("\n===========================================\n");
  
  // On macOS, also show a native alert
  #[cfg(target_os = "macos")]
  {
    use std::process::Command;
    let _ = Command::new("osascript")
      .args(&[
        "-e",
        &format!(r#"display alert "Cedar - Initialization Error" message "{}" as critical"#, message)
      ])
      .output();
  }
}

/// Show an error dialog when API key is not available
fn show_api_key_error() {
  eprintln!("\n===========================================\n");
  eprintln!("ERROR: Cedar requires an OpenAI API key to function.\n");
  eprintln!("The app cannot start without a valid API key.\n");
  eprintln!("Please ensure either:\n");
  eprintln!("1. OPENAI_API_KEY is set in your environment, OR");
  eprintln!("2. The app can fetch a key from cedar-notebook.onrender.com\n");
  eprintln!("For more information, see the README.\n");
  eprintln!("===========================================\n");
  
  // On macOS, also show a native alert
  #[cfg(target_os = "macos")]
  {
    use std::process::Command;
    let _ = Command::new("osascript")
      .args(&[
        "-e",
        r#"display alert "Cedar - API Key Required" message "Cedar requires an OpenAI API key to function.\n\nPlease set OPENAI_API_KEY in your environment or ensure the app can connect to the key server.\n\nSee the README for setup instructions." as critical"#
      ])
      .output();
  }
}
