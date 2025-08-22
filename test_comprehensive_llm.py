#!/usr/bin/env python3
"""
Comprehensive test suite for Cedar LLM functionality.
Tests research loop, file upload, and LLM processing capabilities.
"""

import json
import time
import requests
import subprocess
import os
import sys
from pathlib import Path
import pandas as pd
from datetime import datetime
import hashlib

# Configuration
RENDER_URL = "https://cedar-notebook-nu9j.onrender.com"
AUTH_TOKEN = "3b6e5f09-d5c8-4a9f-8e2a-1c3d7f9b4a56"
LOCAL_PORT = 8080

# Test results collector
test_results = []

def log(message, level="INFO"):
    """Log message with timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}")
    
def record_test(name, success, details=""):
    """Record test result."""
    test_results.append({
        "name": name,
        "success": success,
        "details": details,
        "timestamp": datetime.now().isoformat()
    })
    status = "✅ PASSED" if success else "❌ FAILED"
    log(f"Test '{name}': {status}", "INFO" if success else "ERROR")
    if details:
        log(f"  Details: {details}", "DEBUG")

def fetch_openai_key():
    """Fetch OpenAI API key from Render deployment."""
    log("Fetching OpenAI API key from Render deployment...")
    
    try:
        response = requests.get(
            f"{RENDER_URL}/config/openai_key",
            headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            key = data.get("key", "")
            if key and key.startswith("sk-"):
                log(f"Successfully fetched OpenAI key (ends with ...{key[-4:]})")
                return key
            else:
                log("Invalid key format received", "ERROR")
                return None
        else:
            log(f"Failed to fetch key: {response.status_code}", "ERROR")
            return None
            
    except Exception as e:
        log(f"Error fetching OpenAI key: {e}", "ERROR")
        return None

def start_local_server(openai_key):
    """Start the local Cedar notebook server."""
    log("Starting local Cedar notebook server...")
    
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = openai_key
    env["OPENAI_MODEL"] = "gpt-4o-mini"
    env["RUST_LOG"] = "info,notebook_server=debug"
    env["CEDAR_SERVER_URL"] = f"http://localhost:{LOCAL_PORT}"
    
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
                log("Server is ready")
                return server_process
        except:
            time.sleep(1)
    
    log("Server failed to start", "ERROR")
    server_process.kill()
    return None

def test_health_check():
    """Test server health endpoint."""
    log("Testing health check endpoint...")
    
    try:
        response = requests.get(f"http://localhost:{LOCAL_PORT}/health")
        success = response.status_code == 200
        record_test("Health Check", success, f"Status: {response.status_code}")
        return success
    except Exception as e:
        record_test("Health Check", False, str(e))
        return False

def test_research_loop():
    """Test the research loop LLM functionality."""
    log("Testing research loop (agent loop)...")
    
    try:
        # Test simple query
        payload = {
            "messages": [
                {"role": "user", "content": "What is the capital of France?"}
            ]
        }
        
        response = requests.post(
            f"http://localhost:{LOCAL_PORT}/api/agent_loop",
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            if "response" in result and result["response"]:
                log(f"Research loop response: {result['response'][:200]}...")
                record_test("Research Loop - Simple Query", True, "Got valid response")
                return True
            else:
                record_test("Research Loop - Simple Query", False, "Empty response")
                return False
        else:
            record_test("Research Loop - Simple Query", False, f"Status: {response.status_code}")
            return False
            
    except Exception as e:
        record_test("Research Loop - Simple Query", False, str(e))
        return False

def test_complex_research():
    """Test research loop with complex analysis request."""
    log("Testing complex research analysis...")
    
    try:
        payload = {
            "messages": [
                {"role": "user", "content": "Analyze the pros and cons of electric vehicles vs gasoline cars. Include environmental, economic, and practical considerations."}
            ]
        }
        
        response = requests.post(
            f"http://localhost:{LOCAL_PORT}/api/agent_loop",
            json=payload,
            timeout=60
        )
        
        if response.status_code == 200:
            result = response.json()
            if "response" in result and len(result["response"]) > 100:
                log(f"Complex analysis response length: {len(result['response'])} chars")
                record_test("Research Loop - Complex Analysis", True, "Got comprehensive response")
                return True
            else:
                record_test("Research Loop - Complex Analysis", False, "Response too short")
                return False
        else:
            record_test("Research Loop - Complex Analysis", False, f"Status: {response.status_code}")
            return False
            
    except Exception as e:
        record_test("Research Loop - Complex Analysis", False, str(e))
        return False

def create_test_csv():
    """Create a test CSV file with sample data."""
    log("Creating test CSV file...")
    
    data = {
        "Product": ["Laptop", "Phone", "Tablet", "Monitor", "Keyboard"],
        "Category": ["Electronics", "Electronics", "Electronics", "Electronics", "Accessories"],
        "Price": [1200, 800, 600, 350, 75],
        "Stock": [45, 120, 78, 23, 200],
        "Rating": [4.5, 4.7, 4.3, 4.6, 4.1]
    }
    
    df = pd.DataFrame(data)
    filepath = "/tmp/test_products.csv"
    df.to_csv(filepath, index=False)
    
    log(f"Created test CSV with {len(df)} rows")
    return filepath

def test_file_upload():
    """Test file upload and LLM processing."""
    log("Testing file upload with LLM analysis...")
    
    csv_path = create_test_csv()
    
    try:
        # Upload the file
        with open(csv_path, 'rb') as f:
            files = {'file': ('test_products.csv', f, 'text/csv')}
            
            response = requests.post(
                f"http://localhost:{LOCAL_PORT}/datasets/upload",
                files=files,
                timeout=60
            )
        
        if response.status_code == 200:
            result = response.json()
            
            # Check for expected fields
            has_metadata = "metadata" in result
            has_columns = "columns" in result
            has_julia_code = "julia_code" in result
            has_file_info = "csv_file" in result or "parquet_file" in result
            
            if has_metadata and has_columns:
                log("File upload successful with LLM analysis:")
                log(f"  - Metadata: {json.dumps(result.get('metadata', {}), indent=2)[:200]}...")
                log(f"  - Columns analyzed: {len(result.get('columns', []))}")
                
                if has_julia_code:
                    log(f"  - Julia code generated: {len(result.get('julia_code', ''))} chars")
                
                record_test("File Upload - Basic", True, "Upload and analysis successful")
                return result
            else:
                record_test("File Upload - Basic", False, "Missing expected fields")
                return None
        else:
            error_msg = response.text[:200] if response.text else "No error message"
            record_test("File Upload - Basic", False, f"Status: {response.status_code}, Error: {error_msg}")
            return None
            
    except Exception as e:
        record_test("File Upload - Basic", False, str(e))
        return None

def test_dataset_retrieval(dataset_id):
    """Test retrieving uploaded dataset."""
    log(f"Testing dataset retrieval for ID: {dataset_id}")
    
    try:
        response = requests.get(
            f"http://localhost:{LOCAL_PORT}/datasets/{dataset_id}",
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.json()
            log(f"Retrieved dataset with {len(result.get('columns', []))} columns")
            record_test("Dataset Retrieval", True, f"Retrieved dataset {dataset_id}")
            return True
        else:
            record_test("Dataset Retrieval", False, f"Status: {response.status_code}")
            return False
            
    except Exception as e:
        record_test("Dataset Retrieval", False, str(e))
        return False

def test_llm_code_generation():
    """Test LLM code generation for data analysis."""
    log("Testing LLM code generation...")
    
    try:
        payload = {
            "messages": [
                {"role": "user", "content": "Generate Python code to analyze a CSV file with columns: Product, Price, Stock. Calculate total inventory value."}
            ]
        }
        
        response = requests.post(
            f"http://localhost:{LOCAL_PORT}/api/agent_loop",
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            response_text = result.get("response", "")
            
            # Check if response contains code-like content
            has_python = "import" in response_text or "def " in response_text or "pandas" in response_text
            has_analysis = "inventory" in response_text.lower() or "value" in response_text.lower()
            
            if has_python or has_analysis:
                log("Code generation successful")
                record_test("LLM Code Generation", True, "Generated relevant code/analysis")
                return True
            else:
                record_test("LLM Code Generation", False, "No code content found")
                return False
        else:
            record_test("LLM Code Generation", False, f"Status: {response.status_code}")
            return False
            
    except Exception as e:
        record_test("LLM Code Generation", False, str(e))
        return False

def test_multi_turn_conversation():
    """Test multi-turn conversation in research loop."""
    log("Testing multi-turn conversation...")
    
    try:
        # First turn
        payload1 = {
            "messages": [
                {"role": "user", "content": "Remember the number 42. I'll ask you about it later."}
            ]
        }
        
        response1 = requests.post(
            f"http://localhost:{LOCAL_PORT}/api/agent_loop",
            json=payload1,
            timeout=30
        )
        
        if response1.status_code != 200:
            record_test("Multi-turn Conversation", False, "First turn failed")
            return False
        
        # Second turn with context
        payload2 = {
            "messages": [
                {"role": "user", "content": "Remember the number 42. I'll ask you about it later."},
                {"role": "assistant", "content": response1.json().get("response", "")},
                {"role": "user", "content": "What number did I ask you to remember?"}
            ]
        }
        
        response2 = requests.post(
            f"http://localhost:{LOCAL_PORT}/api/agent_loop",
            json=payload2,
            timeout=30
        )
        
        if response2.status_code == 200:
            result = response2.json()
            response_text = result.get("response", "").lower()
            
            if "42" in response_text or "forty-two" in response_text:
                log("Multi-turn conversation maintained context")
                record_test("Multi-turn Conversation", True, "Context preserved")
                return True
            else:
                record_test("Multi-turn Conversation", False, "Lost context")
                return False
        else:
            record_test("Multi-turn Conversation", False, f"Second turn failed: {response2.status_code}")
            return False
            
    except Exception as e:
        record_test("Multi-turn Conversation", False, str(e))
        return False

def print_summary():
    """Print test summary."""
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    
    total = len(test_results)
    passed = sum(1 for t in test_results if t["success"])
    failed = total - passed
    
    print(f"\nTotal Tests: {total}")
    print(f"Passed: {passed} ✅")
    print(f"Failed: {failed} ❌")
    print(f"Success Rate: {(passed/total*100):.1f}%\n")
    
    # Show individual results
    print("Individual Test Results:")
    print("-"*40)
    for test in test_results:
        status = "✅" if test["success"] else "❌"
        print(f"{status} {test['name']}")
        if test["details"] and not test["success"]:
            print(f"   └─ {test['details']}")
    
    print("\n" + "="*80)
    
    # Show sample responses for successful tests
    print("\nSAMPLE LLM RESPONSES:")
    print("-"*40)
    
    return passed == total

def main():
    """Run comprehensive LLM tests."""
    print("\n" + "="*80)
    print("CEDAR LLM COMPREHENSIVE TEST SUITE")
    print("="*80)
    log("Starting comprehensive LLM testing...")
    
    # Fetch OpenAI key
    openai_key = fetch_openai_key()
    if not openai_key:
        log("Cannot proceed without OpenAI key", "ERROR")
        return 1
    
    # Start local server
    server_process = start_local_server(openai_key)
    if not server_process:
        log("Failed to start server", "ERROR")
        return 1
    
    try:
        # Run tests
        log("\n--- RUNNING TEST SUITE ---\n")
        
        # 1. Basic connectivity
        test_health_check()
        time.sleep(1)
        
        # 2. Research loop tests
        test_research_loop()
        time.sleep(2)
        
        test_complex_research()
        time.sleep(2)
        
        # 3. File upload and processing
        upload_result = test_file_upload()
        time.sleep(2)
        
        # 4. Dataset retrieval (if upload succeeded)
        if upload_result and "id" in upload_result:
            test_dataset_retrieval(upload_result["id"])
            time.sleep(1)
        
        # 5. Code generation
        test_llm_code_generation()
        time.sleep(2)
        
        # 6. Multi-turn conversation
        test_multi_turn_conversation()
        
        # Print summary
        all_passed = print_summary()
        
        return 0 if all_passed else 1
        
    finally:
        # Clean up
        log("\nCleaning up...")
        if server_process:
            server_process.terminate()
            server_process.wait(timeout=5)
            log("Server stopped")

if __name__ == "__main__":
    sys.exit(main())
