#\!/usr/bin/env python3
"""
Test that the agent loop works through the Rust backend
"""

import json
import subprocess
import sys
import os

def test_agent_query():
    """Test a simple query through the Rust backend"""
    
    print("\n" + "="*80)
    print("TESTING AGENT LOOP THROUGH NATIVE RUST BACKEND")
    print("="*80)
    
    # Set environment variables
    env = os.environ.copy()
    env["CEDAR_KEY_URL"] = "https://cedar-notebook.onrender.com"
    env["APP_SHARED_TOKEN"] = "403-298-09345-023495"
    
    print("\n[1] Testing through Tauri command...")
    
    # Run the app binary directly with a test command
    app_path = "target/release/app"
    
    if not os.path.exists(app_path):
        print(f"❌ App not found at {app_path}")
        print("   Building app first...")
        subprocess.run(["cargo", "build", "--release", "-p", "app"])
    
    # The Tauri app needs to be tested differently - let's test the backend directly
    print("\n[2] Testing backend directly...")
    
    # Create simple Rust test inline
    test_code = '''
fn main() {
    println\!("Testing Cedar backend agent loop...");
    
    // Set environment
    std::env::set_var("CEDAR_KEY_URL", "https://cedar-notebook.onrender.com");
    std::env::set_var("APP_SHARED_TOKEN", "403-298-09345-023495");
    
    // Create runtime for async
    let runtime = tokio::runtime::Runtime::new().unwrap();
    
    runtime.block_on(async {
        println\!("[TEST] Creating backend...");
        let backend = notebook_server::initialize_native().unwrap();
        
        println\!("[TEST] Submitting query: 2+2=");
        match backend.submit_query("2+2=").await {
            Ok(result) => {
                println\!("[SUCCESS] Result: {}", result);
                if result.contains("4") {
                    println\!("✅ Correct answer received\!");
                } else {
                    println\!("⚠️ Answer doesn't contain '4'");
                }
            }
            Err(e) => {
                eprintln\!("[ERROR] Query failed: {}", e);
                std::process::exit(1);
            }
        }
    });
}
'''
    
    # Write and compile test
    os.makedirs("src/bin", exist_ok=True)
    with open("src/bin/test_backend.rs", "w") as f:
        f.write(test_code)
    
    print("[3] Compiling test...")
    result = subprocess.run(
        ["cargo", "build", "--bin", "test_backend"],
        env=env,
        capture_output=True,
        text=True
    )
    
    if result.returncode \!= 0:
        print(f"Compilation output: {result.stderr}")
        return False
    
    print("[4] Running backend test...")
    result = subprocess.run(
        ["cargo", "run", "--bin", "test_backend"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30
    )
    
    print("\n[OUTPUT]")
    print(result.stdout)
    if result.stderr:
        print("\n[STDERR]")  
        print(result.stderr)
    
    return result.returncode == 0

if __name__ == "__main__":
    success = test_agent_query()
    print("\n" + "="*80)
    if success:
        print("✅ AGENT LOOP TEST PASSED")
    else:
        print("❌ AGENT LOOP TEST FAILED")
    print("="*80)
    sys.exit(0 if success else 1)
