#!/usr/bin/env python3
"""
Test file upload functionality with a mock OpenAI key
This tests the server infrastructure without making actual OpenAI API calls
"""

import requests
import sys
from pathlib import Path

def test_file_upload():
    """Test the file upload endpoint"""
    
    # Create a test CSV file if it doesn't exist
    test_file = Path("test_data.csv")
    if not test_file.exists():
        with open(test_file, 'w') as f:
            f.write("name,age,city\n")
            f.write("Alice,30,New York\n")
            f.write("Bob,25,Los Angeles\n")
            f.write("Charlie,35,Chicago\n")
    
    # Test the upload endpoint
    url = "http://localhost:8080/datasets/upload"
    
    print(f"Testing file upload to {url}")
    print(f"Uploading file: {test_file}")
    
    with open(test_file, 'rb') as f:
        files = {'file': (test_file.name, f, 'text/csv')}
        
        try:
            response = requests.post(url, files=files)
            
            print(f"\nStatus Code: {response.status_code}")
            print(f"Response Headers: {dict(response.headers)}")
            
            if response.status_code == 200:
                print("\n✅ Upload successful!")
                print("Response data:")
                import json
                print(json.dumps(response.json(), indent=2))
            else:
                print(f"\n❌ Upload failed with status {response.status_code}")
                print("Response:")
                print(response.text)
                
        except requests.exceptions.ConnectionError:
            print("\n❌ Could not connect to server. Is it running?")
            print("Start the server with: OPENAI_API_KEY=sk-test... cargo run --bin notebook_server")
            return 1
        except Exception as e:
            print(f"\n❌ Error during upload: {e}")
            return 1
    
    return 0

if __name__ == "__main__":
    # First check if server is running
    try:
        health = requests.get("http://localhost:8080/health", timeout=1)
        if health.status_code != 200:
            print("❌ Server health check failed")
            sys.exit(1)
        print("✅ Server is running")
    except:
        print("❌ Server is not running. Start it with:")
        print("   OPENAI_API_KEY=sk-your-key cargo run --bin notebook_server")
        sys.exit(1)
    
    # Test the upload
    sys.exit(test_file_upload())
