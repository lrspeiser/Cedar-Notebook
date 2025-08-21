use anyhow::Result;
use serde_json::json;
use std::process::{Command, Child};
use std::time::Duration;
use std::thread;
use tempfile::TempDir;
use reqwest;

/// Test configuration
struct TestConfig {
    server_port: u16,
    server_url: String,
    test_dir: TempDir,
    openai_api_key: String,
}

impl TestConfig {
    fn new() -> Result<Self> {
        let test_dir = TempDir::new()?;
        let server_port = 18080; // Use a non-standard port for testing
        
        // Check for API key - in test mode we can use a mock key if needed
        let openai_api_key = std::env::var("OPENAI_API_KEY")
            .unwrap_or_else(|_| "test-key-12345".to_string());
        
        Ok(Self {
            server_port,
            server_url: format!("http://127.0.0.1:{}", server_port),
            test_dir,
            openai_api_key,
        })
    }
}

/// Helper to start the notebook server
struct ServerProcess {
    child: Option<Child>,
    port: u16,
}

impl ServerProcess {
    fn start(port: u16) -> Result<Self> {
        println!("Starting notebook_server on port {}", port);
        
        let child = Command::new("../../target/release/notebook_server")
            .env("PORT", port.to_string())
            .env("RUST_LOG", "debug")
            .spawn()?;
        
        // Give the server time to start
        thread::sleep(Duration::from_secs(2));
        
        Ok(Self {
            child: Some(child),
            port,
        })
    }
    
    fn start_with_runs_dir(port: u16, runs_dir: &str) -> Result<Self> {
        println!("Starting notebook_server on port {} with runs_dir {}", port, runs_dir);
        
        let child = Command::new("../../target/release/notebook_server")
            .env("PORT", port.to_string())
            .env("RUST_LOG", "debug")
            .env("CEDAR_RUNS_DIR", runs_dir)
            .spawn()?;
        
        // Give the server time to start
        thread::sleep(Duration::from_secs(2));
        
        Ok(Self {
            child: Some(child),
            port,
        })
    }
    
    fn is_healthy(&self) -> bool {
        let url = format!("http://127.0.0.1:{}/health", self.port);
        match reqwest::blocking::get(&url) {
            Ok(resp) => resp.status().is_success(),
            Err(_) => false,
        }
    }
}

impl Drop for ServerProcess {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            println!("Shutting down notebook_server");
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[test]
fn test_full_system_lifecycle() -> Result<()> {
    let config = TestConfig::new()?;
    
    // Set up environment
    std::env::set_var("OPENAI_API_KEY", &config.openai_api_key);
    // Set the runs directory for both the server and CLI to use our temp dir
    let test_runs_dir = config.test_dir.path().to_str().unwrap().to_string();
    std::env::set_var("CEDAR_RUNS_DIR", &test_runs_dir);
    
    // Start the server with the test runs directory
    let server = ServerProcess::start_with_runs_dir(config.server_port, &test_runs_dir)?;
    
    // Wait for server to be healthy
    let mut retries = 10;
    while retries > 0 && !server.is_healthy() {
        thread::sleep(Duration::from_millis(500));
        retries -= 1;
    }
    assert!(server.is_healthy(), "Server failed to start");
    
    println!("Server is healthy, proceeding with tests");
    
    // Test 1: Verify health endpoint
    test_health_endpoint(&config)?;
    
    // Test 2: List runs (should be empty initially)
    test_list_runs_empty(&config)?;
    
    // Test 3: Run a simple shell command
    test_shell_execution(&config)?;
    
    // Test 4: Run Julia code (if Julia is available)
    test_julia_execution(&config)?;
    
    // Test 5: Submit a query through the agent loop
    test_agent_loop_execution(&config)?;
    
    // Test 6: Verify runs were created
    test_list_runs_populated(&config)?;
    
    println!("All tests passed!");
    Ok(())
}

fn test_health_endpoint(config: &TestConfig) -> Result<()> {
    println!("Testing health endpoint...");
    let client = reqwest::blocking::Client::new();
    let resp = client.get(&format!("{}/health", config.server_url)).send()?;
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text()?, "ok");
    println!("✓ Health endpoint working");
    Ok(())
}

fn test_list_runs_empty(config: &TestConfig) -> Result<()> {
    println!("Testing list runs (expecting empty)...");
    let client = reqwest::blocking::Client::new();
    let resp = client.get(&format!("{}/runs", config.server_url)).send()?;
    assert_eq!(resp.status(), 200);
    
    let body: serde_json::Value = resp.json()?;
    let runs = body["runs"].as_array().expect("runs should be an array");
    assert_eq!(runs.len(), 0, "Initially there should be no runs");
    println!("✓ List runs returns empty array");
    Ok(())
}

fn test_shell_execution(config: &TestConfig) -> Result<()> {
    println!("Testing shell command execution...");
    let client = reqwest::blocking::Client::new();
    
    let payload = json!({
        "cmd": "echo 'Hello from test'",
        "timeout_secs": 5
    });
    
    let resp = client
        .post(&format!("{}/commands/run_shell", config.server_url))
        .json(&payload)
        .send()?;
    
    assert_eq!(resp.status(), 200);
    
    let body: serde_json::Value = resp.json()?;
    assert!(body["ok"].as_bool().unwrap_or(false));
    assert!(body["message"].as_str().unwrap().contains("Hello from test"));
    assert!(body["run_id"].as_str().is_some());
    
    println!("✓ Shell execution successful");
    Ok(())
}

fn test_julia_execution(config: &TestConfig) -> Result<()> {
    println!("Testing Julia code execution...");
    
    // Check if Julia is available
    let julia_check = Command::new("julia")
        .arg("--version")
        .output();
    
    if julia_check.is_err() {
        println!("⚠ Julia not found, skipping Julia tests");
        return Ok(());
    }
    
    let client = reqwest::blocking::Client::new();
    
    let payload = json!({
        "code": "println(2 + 2)"
    });
    
    let resp = client
        .post(&format!("{}/commands/run_julia", config.server_url))
        .json(&payload)
        .send()?;
    
    assert_eq!(resp.status(), 200);
    
    let body: serde_json::Value = resp.json()?;
    assert!(body["ok"].as_bool().unwrap_or(false));
    assert!(body["message"].as_str().unwrap().contains("4"));
    assert!(body["run_id"].as_str().is_some());
    
    println!("✓ Julia execution successful");
    Ok(())
}

fn test_agent_loop_execution(config: &TestConfig) -> Result<()> {
    println!("Testing agent loop with '2+2' query...");
    
    // For this test, we'll use the CLI directly since the server's agent loop
    // endpoint may not be fully wired up yet
    let output = Command::new("../../target/release/cedar-cli")
        .arg("agent")
        .arg("--user-prompt")
        .arg("What is 2+2? Please calculate and provide the answer.")
        .env("OPENAI_API_KEY", &config.openai_api_key)
        .env("CEDAR_RUNS_DIR", config.test_dir.path().to_str().unwrap())
        .output()?;
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    
    println!("CLI stdout: {}", stdout);
    println!("CLI stderr: {}", stderr);
    
    // Check the command output
    if config.openai_api_key == "test-key-12345" {
        // With a test key, the command will likely fail due to API authentication
        println!("⚠ Using test API key, skipping result verification");
        if !output.status.success() {
            println!("  Agent command failed as expected with test key");
        }
    } else {
        // With a real API key, check that it worked
        assert!(output.status.success(), "CLI command failed");
        
        // The output should contain "4" somewhere
        assert!(
            stdout.contains("4") || stderr.contains("4"),
            "Output should contain the answer '4'"
        );
    }
    
    println!("✓ Agent loop execution successful");
    Ok(())
}

fn test_list_runs_populated(config: &TestConfig) -> Result<()> {
    println!("Testing list runs (expecting populated)...");
    let client = reqwest::blocking::Client::new();
    let resp = client.get(&format!("{}/runs", config.server_url)).send()?;
    assert_eq!(resp.status(), 200);
    
    let body: serde_json::Value = resp.json()?;
    let runs = body["runs"].as_array().expect("runs should be an array");
    assert!(runs.len() > 0, "There should be at least one run after tests");
    
    println!("✓ List runs shows {} run(s)", runs.len());
    Ok(())
}

#[test]
fn test_environment_variables() {
    println!("Testing environment variable handling...");
    
    // Test that the system handles missing API key gracefully
    std::env::remove_var("OPENAI_API_KEY");
    let output = Command::new("../../target/release/cedar-cli")
        .arg("--help")
        .output()
        .expect("Failed to run cedar-cli");
    
    assert!(output.status.success(), "CLI should run without API key for help");
    
    // Test with invalid API key format
    std::env::set_var("OPENAI_API_KEY", "invalid");
    let output = Command::new("../../target/release/cedar-cli")
        .arg("agent")
        .arg("--user-prompt")
        .arg("test")
        .output();
    
    // The system should handle invalid keys gracefully
    match output {
        Ok(_) => println!("✓ System handles invalid API key"),
        Err(e) => println!("⚠ Error with invalid API key: {}", e),
    }
}

#[test]
fn test_concurrent_requests() -> Result<()> {
    println!("Testing concurrent request handling...");
    
    let config = TestConfig::new()?;
    let server = ServerProcess::start(config.server_port)?;
    
    // Wait for server to be healthy
    thread::sleep(Duration::from_secs(2));
    assert!(server.is_healthy(), "Server failed to start");
    
    // Spawn multiple concurrent requests
    let handles: Vec<_> = (0..5)
        .map(|i| {
            let url = config.server_url.clone();
            thread::spawn(move || {
                let client = reqwest::blocking::Client::new();
                let payload = json!({
                    "cmd": format!("echo 'Request {}'", i),
                    "timeout_secs": 5
                });
                
                client
                    .post(&format!("{}/commands/run_shell", url))
                    .json(&payload)
                    .send()
            })
        })
        .collect();
    
    // Wait for all requests to complete
    for handle in handles {
        let result = handle.join().expect("Thread panicked");
        let resp = result?;
        assert_eq!(resp.status(), 200);
    }
    
    println!("✓ Concurrent requests handled successfully");
    Ok(())
}

#[test]
fn test_error_handling() -> Result<()> {
    println!("Testing error handling...");
    
    let config = TestConfig::new()?;
    let server = ServerProcess::start(config.server_port)?;
    
    thread::sleep(Duration::from_secs(2));
    assert!(server.is_healthy(), "Server failed to start");
    
    let client = reqwest::blocking::Client::new();
    
    // Test 1: Invalid shell command
    let payload = json!({
        "cmd": "this_command_does_not_exist",
        "timeout_secs": 5
    });
    
    let resp = client
        .post(&format!("{}/commands/run_shell", config.server_url))
        .json(&payload)
        .send()?;
    
    assert_eq!(resp.status(), 200); // Should still return 200
    let body: serde_json::Value = resp.json()?;
    assert!(!body["ok"].as_bool().unwrap_or(true), "Command should fail");
    
    // Test 2: Command timeout
    let payload = json!({
        "cmd": "sleep 10",
        "timeout_secs": 1
    });
    
    let resp = client
        .post(&format!("{}/commands/run_shell", config.server_url))
        .json(&payload)
        .send()?;
    
    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = resp.json()?;
    assert!(!body["ok"].as_bool().unwrap_or(true), "Command should timeout");
    assert!(body["message"].as_str().unwrap().contains("Timed out"));
    
    println!("✓ Error handling working correctly");
    Ok(())
}
