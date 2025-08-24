// Test program to demonstrate the full agent loop in Rust
// Compile with: rustc test_rust_backend.rs -L target/release/deps --extern notebook_core=target/release/deps/libnotebook_core.rlib

use std::path::PathBuf;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Enable detailed logging
    std::env::set_var("RUST_LOG", "debug");
    std::env::set_var("CEDAR_LOG_LLM_JSON", "1");
    std::env::set_var("CEDAR_KEY_URL", "https://cedar-notebook.onrender.com");
    std::env::set_var("APP_SHARED_TOKEN", "403-298-09345-023495");
    
    env_logger::init();
    
    println!("\n{'='*80}");
    println!("RUST BACKEND AGENT LOOP - COMPLETE FLOW");
    println!("{'='*80}\n");
    
    // Import the actual functions from notebook_core
    use notebook_core::agent_loop::{agent_loop, AgentConfig};
    use notebook_core::key_manager::KeyManager;
    
    let query = "2+2=";
    println!(">>> USER QUERY: {}", query);
    
    // Initialize key manager
    println!("\n>>> INITIALIZING KEY MANAGER");
    let key_manager = KeyManager::new()?;
    
    // Fetch API key
    println!(">>> FETCHING API KEY FROM ONRENDER SERVER");
    let api_key = key_manager.get_api_key().await?;
    println!(">>> GOT API KEY: {}...{}", &api_key[..10], &api_key[api_key.len()-4..]);
    
    // Create run directory
    let run_id = format!("run_{}", chrono::Utc::now().timestamp_millis());
    let run_dir = PathBuf::from("/tmp").join(&run_id);
    std::fs::create_dir_all(&run_dir)?;
    println!("\n>>> CREATED RUN DIRECTORY: {:?}", run_dir);
    
    // Configure agent
    println!("\n>>> CONFIGURING AGENT");
    let config = AgentConfig {
        openai_api_key: api_key.clone(),
        openai_model: "gpt-4o-mini".to_string(),
        openai_base: None,
        relay_url: Some("https://cedar-notebook.onrender.com".to_string()),
        app_shared_token: Some("403-298-09345-023495".to_string()),
    };
    println!("   Model: {}", config.openai_model);
    println!("   Relay URL: {:?}", config.relay_url);
    
    // Run agent loop
    println!("\n>>> STARTING AGENT LOOP");
    println!("   Max turns: 10");
    
    let result = agent_loop(&run_dir, query, 10, config).await?;
    
    println!("\n>>> AGENT LOOP COMPLETED");
    println!("   Turns used: {}", result.turns_used);
    println!("   Final output: {:?}", result.final_output);
    
    // Check what files were created
    println!("\n>>> FILES CREATED IN RUN DIRECTORY:");
    if let Ok(entries) = std::fs::read_dir(&run_dir) {
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                println!("   - {:?}", path.file_name().unwrap());
                
                // Read and display content of text files
                if let Some(ext) = path.extension() {
                    if ext == "json" || ext == "jl" || ext == "txt" {
                        if let Ok(content) = std::fs::read_to_string(&path) {
                            println!("     Content preview: {}", 
                                if content.len() > 100 { 
                                    format!("{}...", &content[..100]) 
                                } else { 
                                    content.clone() 
                                });
                        }
                    }
                }
            }
        }
    }
    
    println!("\n{'='*80}");
    println!("✅ TEST COMPLETE");
    println!("{'='*80}");
    
    Ok(())
}