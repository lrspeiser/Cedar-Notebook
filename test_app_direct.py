#!/usr/bin/env python3
"""
Test the app binary directly to show the complete agent loop flow
"""

import subprocess
import os
import sys
import json
import time
import tempfile

def test_app_with_logging():
    """Run the app binary with full logging to show agent loop"""
    
    print("\n" + "="*80)
    print("TESTING CEDAR APP BINARY - FULL AGENT LOOP")
    print("="*80)
    
    # Set up environment with full logging
    env = os.environ.copy()
    env["RUST_LOG"] = "debug,notebook_core=trace,notebook_server=trace"
    env["CEDAR_LOG_LLM_JSON"] = "1"
    env["CEDAR_KEY_URL"] = "https://cedar-notebook.onrender.com"
    env["APP_SHARED_TOKEN"] = "403-298-09345-023495"
    
    # The app binary path
    app_path = "/Users/leonardspeiser/Projects/cedarcli/.conductor/manama/target/release/app"
    
    if not os.path.exists(app_path):
        print(f"❌ App binary not found at {app_path}")
        print("Please build with: cd apps/desktop && npm run tauri:build")
        return False
    
    print(f"✅ Found app binary: {app_path}")
    print("\nEnvironment settings:")
    print(f"  RUST_LOG: {env['RUST_LOG']}")
    print(f"  CEDAR_LOG_LLM_JSON: {env['CEDAR_LOG_LLM_JSON']}")
    print(f"  CEDAR_KEY_URL: {env['CEDAR_KEY_URL']}")
    print(f"  APP_SHARED_TOKEN: {env['APP_SHARED_TOKEN'][:10]}...")
    
    # Since the app is a Tauri app with a UI, we can't easily call it directly
    # Let's create a simple Rust test that uses the same backend code
    
    print("\n" + "="*80)
    print("CREATING TEST HARNESS")
    print("="*80)
    
    test_code = '''
use notebook_core::agent_loop::{agent_loop, AgentConfig};
use notebook_core::key_manager::KeyManager;
use std::path::PathBuf;

#[tokio::main]
async fn main() {
    // Enable logging
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info,notebook_core=debug")
    ).init();
    
    let query = "2+2=";
    println!("\\n>>> QUERY: {}", query);
    
    // Initialize and run
    let key_manager = KeyManager::new().expect("Failed to create key manager");
    println!(">>> Fetching API key...");
    
    let api_key = key_manager.get_api_key().await.expect("Failed to get API key");
    println!(">>> Got API key: {}...{}", &api_key[..10], &api_key[api_key.len()-4..]);
    
    let run_dir = PathBuf::from("/tmp").join(format!("test_{}", chrono::Utc::now().timestamp_millis()));
    std::fs::create_dir_all(&run_dir).expect("Failed to create run dir");
    
    let config = AgentConfig {
        openai_api_key: api_key,
        openai_model: "gpt-4o-mini".to_string(),
        openai_base: None,
        relay_url: std::env::var("CEDAR_KEY_URL").ok(),
        app_shared_token: std::env::var("APP_SHARED_TOKEN").ok(),
    };
    
    println!("\\n>>> Starting agent loop...");
    match agent_loop(&run_dir, query, 10, config).await {
        Ok(result) => {
            println!("\\n>>> ✅ SUCCESS");
            println!(">>> Turns used: {}", result.turns_used);
            println!(">>> Final output: {}", result.final_output.unwrap_or_else(|| "No output".to_string()));
        }
        Err(e) => {
            println!("\\n>>> ❌ ERROR: {}", e);
        }
    }
}
'''
    
    # Create a temporary Rust project
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Creating test project in {tmpdir}")
        
        # Create Cargo.toml
        cargo_toml = f'''[package]
name = "test_cedar"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = {{ version = "1", features = ["full"] }}
env_logger = "0.11"
chrono = "0.4"
notebook_core = {{ path = "{os.path.abspath('crates/notebook_core')}" }}
'''
        
        with open(os.path.join(tmpdir, "Cargo.toml"), "w") as f:
            f.write(cargo_toml)
        
        # Create src directory and main.rs
        os.makedirs(os.path.join(tmpdir, "src"))
        with open(os.path.join(tmpdir, "src", "main.rs"), "w") as f:
            f.write(test_code)
        
        print("\n" + "="*80)
        print("BUILDING TEST BINARY")
        print("="*80)
        
        # Build the test
        build_result = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=tmpdir,
            env=env,
            capture_output=True,
            text=True
        )
        
        if build_result.returncode != 0:
            print(f"❌ Build failed:")
            print(build_result.stderr)
            return False
        
        print("✅ Test binary built successfully")
        
        # Run the test
        print("\n" + "="*80)
        print("RUNNING AGENT LOOP TEST")
        print("="*80)
        
        test_binary = os.path.join(tmpdir, "target", "release", "test_cedar")
        
        # Run with real-time output
        process = subprocess.Popen(
            [test_binary],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        # Print output in real-time
        for line in iter(process.stdout.readline, ''):
            if line:
                print(line.rstrip())
        
        process.wait()
        
        if process.returncode == 0:
            print("\n✅ Agent loop test completed successfully!")
            return True
        else:
            print(f"\n❌ Test failed with exit code {process.returncode}")
            return False

if __name__ == "__main__":
    success = test_app_with_logging()
    sys.exit(0 if success else 1)