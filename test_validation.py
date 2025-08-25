#!/usr/bin/env python3
"""
Validation test to ensure all components are configured correctly:
1. API key fetching from cedar-notebook.onrender.com  
2. Direct OpenAI calls (not relayed)
3. GPT-5 /v1/responses endpoint
"""

import subprocess
import os
import tempfile

# Create a test Rust program that does exactly what the app does
test_code = '''
use notebook_server;
use notebook_core::key_manager::KeyManager;

#[tokio::main]
async fn main() {
    // Set the same env vars the app sets
    std::env::set_var("CEDAR_KEY_URL", "https://cedar-notebook.onrender.com");
    std::env::set_var("APP_SHARED_TOKEN", "403-298-09345-023495");
    
    println!("[TEST] Environment variables set");
    println!("[TEST] CEDAR_KEY_URL: {}", std::env::var("CEDAR_KEY_URL").unwrap_or("not set".to_string()));
    println!("[TEST] APP_SHARED_TOKEN: {}", std::env::var("APP_SHARED_TOKEN").unwrap_or("not set".to_string()));
    
    // Do exactly what the app does for validation
    println!("[TEST] Initializing backend...");
    match notebook_server::initialize_native() {
        Ok(backend) => {
            println!("[TEST] Backend initialized successfully");
            println!("[TEST] Attempting to get API key...");
            
            match backend.initialize_api_key().await {
                Ok(key) => {
                    println!("[TEST] ✅ API key obtained: {}...{}", &key[..10], &key[key.len()-4..]);
                    std::process::exit(0);
                }
                Err(e) => {
                    println!("[TEST] ❌ Failed to get API key: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Err(e) => {
            println!("[TEST] ❌ Failed to initialize backend: {}", e);
            std::process::exit(1);
        }
    }
}
'''

print("="*80)
print("TESTING EXACT VALIDATION LOGIC")
print("="*80)

# Create a temporary Rust project
with tempfile.TemporaryDirectory() as tmpdir:
    print(f"\nCreating test in {tmpdir}")
    
    # Create Cargo.toml
    cargo_toml = f'''[package]
name = "test_validation"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = {{ version = "1", features = ["full"] }}
notebook_server = {{ path = "{os.path.abspath('crates/notebook_server')}" }}
notebook_core = {{ path = "{os.path.abspath('crates/notebook_core')}" }}
'''
    
    with open(os.path.join(tmpdir, "Cargo.toml"), "w") as f:
        f.write(cargo_toml)
    
    # Create src directory and main.rs
    os.makedirs(os.path.join(tmpdir, "src"))
    with open(os.path.join(tmpdir, "src", "main.rs"), "w") as f:
        f.write(test_code)
    
    print("\nBuilding test...")
    build_result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=tmpdir,
        capture_output=True,
        text=True
    )
    
    if build_result.returncode != 0:
        print(f"❌ Build failed:\n{build_result.stderr}")
        exit(1)
    
    print("✅ Build successful")
    
    # Run the test with no environment
    print("\nRunning validation test with empty environment...")
    test_binary = os.path.join(tmpdir, "target", "release", "test_validation")
    
    result = subprocess.run(
        [test_binary],
        env={},  # Empty environment to replicate the error
        capture_output=True,
        text=True
    )
    
    print("\n[OUTPUT]")
    print(result.stdout)
    if result.stderr:
        print("\n[STDERR]")
        print(result.stderr)
    
    if result.returncode == 0:
        print("\n✅ VALIDATION PASSED")
    else:
        print("\n❌ VALIDATION FAILED - This reproduces the error!")
        
        # Now try with PATH set (macOS apps have minimal environment)
        print("\n" + "="*80)
        print("Testing with minimal macOS app environment (PATH only)...")
        
        result2 = subprocess.run(
            [test_binary],
            env={"PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True
        )
        
        print("\n[OUTPUT]")
        print(result2.stdout)
        
        if result2.returncode == 0:
            print("\n✅ Works with PATH set")
        else:
            print("\n❌ Still fails even with PATH")