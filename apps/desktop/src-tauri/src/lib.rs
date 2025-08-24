// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use tauri::Manager;
use tauri::menu::{Menu, MenuItemBuilder, SubmenuBuilder};
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
struct FileInfo {
    path: String,
    name: String,
    size: u64,
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
  // CRITICAL: Load environment variables for API key fetching from onrender server
  // See docs/openai-key-flow.md and README.md for complete key management strategy
  // DO NOT REMOVE: This enables fetching keys from cedar-notebook.onrender.com
  load_env_config();
  
  // Validate API key availability before starting
  let api_key_available = validate_api_key_availability();
  
  if !api_key_available {
    // Show error window instead of main app
    show_api_key_error();
    return;
  }
  
  // Start the backend server in a separate thread
  std::thread::spawn(|| {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
      println!("Starting embedded Cedar backend server...");
      if let Err(e) = notebook_server::serve().await {
        eprintln!("Backend server error: {}", e);
      }
    });
  });
  
  // Give the backend a moment to start
  std::thread::sleep(std::time::Duration::from_secs(2));
  
  // Ensure the app appears in the dock on macOS
  #[cfg(target_os = "macos")]
  {
    use tauri::Manager;
    std::thread::spawn(|| {
      std::thread::sleep(std::time::Duration::from_millis(100));
    });
  }
  
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .invoke_handler(tauri::generate_handler![select_file, process_file_at_path])
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

/// Validate that we can access an OpenAI API key
fn validate_api_key_availability() -> bool {
  // Check if we have a local API key
  if std::env::var("OPENAI_API_KEY").is_ok() {
    eprintln!("[cedar] ✅ Local OpenAI API key found");
    return true;
  }
  
  // Try to fetch from remote server
  eprintln!("[cedar] Attempting to fetch API key from remote server...");
  
  let cedar_key_url = std::env::var("CEDAR_KEY_URL")
    .unwrap_or_else(|_| "https://cedar-notebook.onrender.com".to_string());
  let app_token = std::env::var("APP_SHARED_TOKEN")
    .unwrap_or_else(|_| "403-298-09345-023495".to_string());
  
  // Create a blocking runtime for the HTTP request
  let runtime = tokio::runtime::Runtime::new().unwrap();
  let result = runtime.block_on(async {
    test_api_key_fetch(&cedar_key_url, &app_token).await
  });
  
  match result {
    Ok(_) => {
      eprintln!("[cedar] ✅ Successfully validated API key access from {}", cedar_key_url);
      true
    }
    Err(e) => {
      eprintln!("[cedar] ❌ Failed to access API key: {}", e);
      false
    }
  }
}

/// Test fetching API key from remote server
async fn test_api_key_fetch(base_url: &str, token: &str) -> Result<(), String> {
  let client = reqwest::Client::builder()
    .timeout(std::time::Duration::from_secs(10))
    .build()
    .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
  
  let endpoint = format!("{}/config/openai_key", base_url);
  
  let response = client
    .get(&endpoint)
    .header("x-app-token", token)
    .send()
    .await
    .map_err(|e| format!("Network error: {}", e))?;
  
  if !response.status().is_success() {
    return Err(format!("Server returned error: {}", response.status()));
  }
  
  let json: serde_json::Value = response
    .json()
    .await
    .map_err(|e| format!("Invalid response format: {}", e))?;
  
  if let Some(key) = json.get("openai_api_key").and_then(|v| v.as_str()) {
    if key.starts_with("sk-") && key.len() >= 40 {
      return Ok(());
    }
  }
  
  Err("Response does not contain valid OpenAI API key".to_string())
}

/// Show error window when API key is not available
fn show_api_key_error() {
  use tauri::{Builder, WindowBuilder, Manager};
  
  let error_html = r#"<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cedar - API Error</title>
  <style>
    body {
      margin: 0;
      padding: 0;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    }
    .error-container {
      background: white;
      border-radius: 20px;
      padding: 60px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      text-align: center;
      max-width: 500px;
    }
    .error-icon {
      font-size: 80px;
      margin-bottom: 20px;
    }
    h1 {
      color: #333;
      margin: 20px 0;
      font-size: 28px;
    }
    p {
      color: #666;
      line-height: 1.6;
      margin: 20px 0;
      font-size: 16px;
    }
    .error-details {
      background: #f5f5f5;
      border-radius: 10px;
      padding: 20px;
      margin: 30px 0;
      text-align: left;
    }
    .error-details h3 {
      color: #444;
      margin-top: 0;
    }
    .error-details ol {
      color: #666;
      padding-left: 20px;
    }
    .error-details li {
      margin: 10px 0;
    }
    .error-details code {
      background: #e8e8e8;
      padding: 2px 6px;
      border-radius: 3px;
      font-family: 'Courier New', monospace;
    }
    button {
      background: #667eea;
      color: white;
      border: none;
      padding: 12px 30px;
      border-radius: 25px;
      font-size: 16px;
      cursor: pointer;
      margin: 10px;
    }
    button:hover {
      background: #5a67d8;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-icon">❌</div>
    <h1>Unable to access the API for GPT</h1>
    <p>Cedar could not connect to the OpenAI API service. The app requires a valid API key to function.</p>
    
    <div class="error-details">
      <h3>How to fix this:</h3>
      <ol>
        <li>Set your OpenAI API key in the environment:<br>
            <code>export OPENAI_API_KEY="sk-your-key-here"</code></li>
        <li>Or create a config file at:<br>
            <code>~/.cedar/.env</code><br>
            with the line:<br>
            <code>OPENAI_API_KEY=sk-your-key-here</code></li>
        <li>Ensure the Cedar key server is running at:<br>
            <code>https://cedar-notebook.onrender.com</code></li>
      </ol>
    </div>
    
    <button onclick="window.close()">Close</button>
    <button onclick="location.reload()">Retry</button>
  </div>
</body>
</html>"#;
  
  Builder::default()
    .setup(|app| {
      WindowBuilder::new(
        app,
        "error",
        tauri::WindowUrl::App("data:text/html,".parse().unwrap())
      )
      .title("Cedar - API Error")
      .inner_size(600.0, 700.0)
      .resizable(false)
      .center()
      .build()?;
      
      // Set the HTML content
      if let Some(window) = app.get_webview_window("error") {
        let _ = window.eval(&format!("document.write({})", 
          serde_json::to_string(error_html).unwrap()));
      }
      
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("Failed to show error window");
}
