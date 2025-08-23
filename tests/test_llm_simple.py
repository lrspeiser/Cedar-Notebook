#!/usr/bin/env python3
"""
Simple test suite for Cedar LLM functionality using local OpenAI key.
"""

import json
import time
import requests
import subprocess
import os
import sys
from datetime import datetime
import pandas as pd

LOCAL_PORT = 8080

def log(message, level="INFO"):
    """Log message with timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}")

def start_server_with_mock_key():
    """Start server with a mock key for testing configuration only."""
    log("Starting Cedar server with test configuration...")
    
    env = os.environ.copy()
    # Use a mock key for testing - the actual calls won't work but we can test the infrastructure
    env["OPENAI_API_KEY"] = "sk-test-key-for-configuration-only"
    env["OPENAI_MODEL"] = "gpt-4o-mini"
    env["RUST_LOG"] = "info,notebook_server=debug"
    
    server_process = subprocess.Popen(
        ["cargo", "run", "--release", "--bin", "notebook_server"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd="/Users/leonardspeiser/Projects/cedarcli"
    )
    
    # Wait for server to start
    for i in range(30):
        try:
            response = requests.get(f"http://localhost:{LOCAL_PORT}/health", timeout=1)
            if response.status_code == 200:
                log("✅ Server started successfully")
                return server_process
        except:
            time.sleep(1)
    
    log("❌ Server failed to start", "ERROR")
    server_process.kill()
    return None

def test_endpoints():
    """Test various endpoints to see their structure."""
    log("\n=== TESTING ENDPOINTS ===\n")
    
    endpoints = [
        ("GET", "/health", None),
        ("GET", "/datasets", None),
        ("POST", "/api/agent_loop", {
            "messages": [{"role": "user", "content": "Test message"}]
        }),
    ]
    
    results = []
    
    for method, endpoint, data in endpoints:
        url = f"http://localhost:{LOCAL_PORT}{endpoint}"
        log(f"Testing {method} {endpoint}...")
        
        try:
            if method == "GET":
                response = requests.get(url, timeout=5)
            else:
                response = requests.post(url, json=data, timeout=5)
            
            log(f"  Status: {response.status_code}")
            
            if response.status_code == 200:
                try:
                    result = response.json()
                    log(f"  Response structure: {json.dumps(result, indent=2)[:500]}...")
                except:
                    log(f"  Response: {response.text[:200]}...")
            else:
                log(f"  Error: {response.text[:200]}...")
                
            results.append({
                "endpoint": endpoint,
                "method": method,
                "status": response.status_code,
                "success": response.status_code == 200
            })
            
        except Exception as e:
            log(f"  Exception: {e}", "ERROR")
            results.append({
                "endpoint": endpoint,
                "method": method,
                "status": "error",
                "success": False
            })
    
    return results

def test_file_upload_structure():
    """Test file upload endpoint structure."""
    log("\n=== TESTING FILE UPLOAD STRUCTURE ===\n")
    
    # Create a simple CSV
    data = {
        "Name": ["Alice", "Bob"],
        "Age": [25, 30],
        "City": ["NYC", "LA"]
    }
    
    df = pd.DataFrame(data)
    filepath = "/tmp/test_simple.csv"
    df.to_csv(filepath, index=False)
    
    log("Created test CSV file")
    
    try:
        with open(filepath, 'rb') as f:
            files = {'file': ('test.csv', f, 'text/csv')}
            
            log("Attempting file upload...")
            response = requests.post(
                f"http://localhost:{LOCAL_PORT}/datasets/upload",
                files=files,
                timeout=10
            )
        
        log(f"Upload status: {response.status_code}")
        
        if response.text:
            try:
                result = response.json()
                log(f"Response structure:\n{json.dumps(result, indent=2)[:1000]}...")
            except:
                log(f"Response text: {response.text[:500]}...")
                
        return response.status_code == 200
        
    except Exception as e:
        log(f"Upload error: {e}", "ERROR")
        return False

def analyze_server_logs(process):
    """Read and analyze server logs."""
    log("\n=== SERVER LOG ANALYSIS ===\n")
    
    # Read some stderr output
    try:
        # Non-blocking read of stderr
        import select
        import fcntl
        import os
        
        # Make stderr non-blocking
        fd = process.stderr.fileno()
        fl = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
        
        logs = []
        while True:
            try:
                line = process.stderr.readline()
                if not line:
                    break
                logs.append(line.strip())
                if len(logs) > 100:  # Limit log lines
                    break
            except:
                break
        
        if logs:
            log("Recent server logs:")
            for line in logs[-20:]:  # Show last 20 lines
                if "ERROR" in line or "WARN" in line:
                    print(f"  ⚠️  {line}")
                elif "INFO" in line:
                    print(f"  ℹ️  {line}")
                else:
                    print(f"     {line}")
        
    except Exception as e:
        log(f"Could not read server logs: {e}")

def main():
    """Run simple infrastructure tests."""
    print("\n" + "="*80)
    print("CEDAR INFRASTRUCTURE TEST")
    print("="*80)
    log("Testing Cedar server infrastructure and endpoints...")
    
    server_process = start_server_with_mock_key()
    if not server_process:
        return 1
    
    try:
        # Test endpoints
        endpoint_results = test_endpoints()
        
        # Test file upload
        upload_success = test_file_upload_structure()
        
        # Analyze logs
        analyze_server_logs(server_process)
        
        # Summary
        print("\n" + "="*80)
        print("TEST SUMMARY")
        print("="*80)
        
        print("\nEndpoint Test Results:")
        for result in endpoint_results:
            status_icon = "✅" if result["success"] else "❌"
            print(f"  {status_icon} {result['method']:6} {result['endpoint']:30} - Status: {result['status']}")
        
        print(f"\nFile Upload Test: {'✅ Success' if upload_success else '❌ Failed'}")
        
        print("\n" + "="*80)
        print("\nNOTE: This test uses a mock API key, so LLM calls won't actually work.")
        print("      It only tests the server infrastructure and endpoint availability.")
        print("      To test actual LLM functionality, set OPENAI_API_KEY environment variable.")
        print("="*80)
        
        return 0
        
    finally:
        log("\nStopping server...")
        server_process.terminate()
        try:
            server_process.wait(timeout=5)
        except:
            server_process.kill()
        log("Server stopped")

if __name__ == "__main__":
    sys.exit(main())
