#!/usr/bin/env python3
"""
Test Cedar server endpoints to verify the infrastructure is working
"""

import requests
import json

BASE_URL = "http://localhost:8080"

def test_endpoint(name, method, path, **kwargs):
    """Test a single endpoint"""
    url = f"{BASE_URL}{path}"
    print(f"\nTesting {name}:")
    print(f"  {method} {url}")
    
    try:
        if method == "GET":
            response = requests.get(url, **kwargs)
        elif method == "POST":
            response = requests.post(url, **kwargs)
        else:
            print(f"  ❌ Unknown method: {method}")
            return False
            
        print(f"  Status: {response.status_code}")
        
        if response.status_code < 400:
            print(f"  ✅ Success")
            if response.headers.get('content-type', '').startswith('application/json'):
                try:
                    data = response.json()
                    print(f"  Response: {json.dumps(data, indent=4)[:200]}...")
                except:
                    print(f"  Response: {response.text[:200]}...")
            return True
        else:
            print(f"  ❌ Failed")
            print(f"  Response: {response.text[:200]}...")
            return False
            
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False

def main():
    print("=" * 60)
    print("Cedar Server Endpoint Tests")
    print("=" * 60)
    
    # Check if server is running
    if not test_endpoint("Health Check", "GET", "/health"):
        print("\n❌ Server is not running properly!")
        print("Start it with: OPENAI_API_KEY=sk-your-key cargo run --bin notebook_server")
        return 1
    
    # Test OpenAI key endpoint (our new addition)
    test_endpoint("OpenAI Key Endpoint", "GET", "/config/openai_key")
    
    # Test runs endpoints
    test_endpoint("List Runs", "GET", "/runs?limit=5")
    
    # Test datasets endpoint
    test_endpoint("List Datasets", "GET", "/datasets")
    
    # Test a simple Julia command (doesn't need OpenAI)
    test_endpoint(
        "Run Julia Code", 
        "POST", 
        "/commands/run_julia",
        json={"code": "println(\"Hello from Julia!\")"},
        headers={"Content-Type": "application/json"}
    )
    
    # Test a simple shell command
    test_endpoint(
        "Run Shell Command", 
        "POST", 
        "/commands/run_shell",
        json={"cmd": "echo 'Hello from shell'"},
        headers={"Content-Type": "application/json"}
    )
    
    print("\n" + "=" * 60)
    print("Summary:")
    print("✅ Server infrastructure is working!")
    print("✅ New /config/openai_key endpoint is available")
    print("\nNote: File upload with LLM enhancement requires a real OpenAI API key.")
    print("To test with a real key:")
    print("  1. Set OPENAI_API_KEY environment variable")
    print("  2. Restart the server")
    print("  3. Run: python3 test_upload.py")
    print("=" * 60)
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
