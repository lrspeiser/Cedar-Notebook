#!/usr/bin/env python3
"""
Debug the LLM call issue in the upload flow
"""

import requests
import json
import sys
import os
import time
import subprocess

RENDER_SERVER = "https://cedar-notebook.onrender.com"
LOCAL_SERVER = "http://localhost:8080"
TOKEN = "403-298-09345-023495"

def fetch_key_and_start_server():
    """Fetch key from Render and start local server with debug output"""
    print("Fetching OpenAI key from Render...")
    
    headers = {"x-app-token": TOKEN}
    response = requests.get(f"{RENDER_SERVER}/v1/key", headers=headers, timeout=10)
    
    if response.status_code != 200:
        print(f"Failed to fetch key: {response.status_code}")
        return None, None
    
    data = response.json()
    api_key = data.get("openai_api_key")
    print(f"✅ Got key: {api_key[:6]}...{api_key[-4:]}")
    
    # Start server with debug logging
    print("\nStarting server with debug logging...")
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = api_key
    env["RUST_LOG"] = "debug"  # Enable debug logging
    env["CEDAR_LOG_LLM_JSON"] = "1"  # Log LLM responses
    
    server_proc = subprocess.Popen(
        ["cargo", "run", "--release", "--bin", "notebook_server"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,  # Combine stderr with stdout
        text=True,
        bufsize=1  # Line buffered
    )
    
    # Start a thread to print server output
    import threading
    def print_output():
        for line in server_proc.stdout:
            if line.strip():
                print(f"[SERVER] {line.rstrip()}")
    
    output_thread = threading.Thread(target=print_output, daemon=True)
    output_thread.start()
    
    # Wait for server to be ready
    for i in range(20):
        try:
            response = requests.get(f"{LOCAL_SERVER}/health", timeout=1)
            if response.status_code == 200:
                print("✅ Server is ready")
                return api_key, server_proc
        except:
            pass
        time.sleep(1)
    
    print("❌ Server failed to start")
    server_proc.terminate()
    return None, None

def test_simple_upload():
    """Test with a minimal CSV file"""
    csv_content = """name,age
Alice,30
Bob,25"""
    
    with open("simple.csv", "w") as f:
        f.write(csv_content)
    
    print("\nUploading simple.csv...")
    
    with open("simple.csv", 'rb') as f:
        files = {'file': ('simple.csv', f, 'text/csv')}
        
        try:
            response = requests.post(
                f"{LOCAL_SERVER}/datasets/upload",
                files=files,
                timeout=60
            )
            
            print(f"Response status: {response.status_code}")
            
            if response.status_code == 200:
                print("✅ Upload successful!")
                print(json.dumps(response.json(), indent=2))
            else:
                print(f"❌ Upload failed: {response.text}")
                
        except Exception as e:
            print(f"❌ Error: {e}")

def main():
    print("Debug Test for LLM Call Issue")
    print("="*60)
    
    api_key, server_proc = fetch_key_and_start_server()
    
    if not server_proc:
        print("Failed to start server")
        return 1
    
    try:
        # Give server a moment to fully initialize
        time.sleep(2)
        
        # Test the upload
        test_simple_upload()
        
        # Give time to see any error output
        time.sleep(5)
        
    finally:
        print("\n🛑 Stopping server...")
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except:
            server_proc.kill()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
