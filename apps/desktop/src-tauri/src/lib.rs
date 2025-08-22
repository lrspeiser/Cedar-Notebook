#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  // CRITICAL: Load environment variables for API key fetching from onrender server
  // See docs/openai-key-flow.md and README.md for complete key management strategy
  // DO NOT REMOVE: This enables fetching keys from cedar-notebook.onrender.com
  load_env_config();
  
  tauri::Builder::default()
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
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
