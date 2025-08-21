#!/usr/bin/env python3
import requests
import os
import time

# Start the server first if not already running
print("Testing file upload to Cedar backend...")

# Check if server is running
try:
    response = requests.get("http://localhost:8080/health")
    if response.text == "ok":
        print("✓ Server is running")
except:
    print("✗ Server is not running. Please start it first with: cargo run --release --bin cedar-bundle")
    exit(1)

# Test file upload
test_file = "test_data.csv"

if not os.path.exists(test_file):
    print(f"✗ Test file {test_file} not found")
    exit(1)

print(f"Uploading {test_file}...")

# Create multipart form data
with open(test_file, 'rb') as f:
    files = {'files': (test_file, f, 'text/csv')}
    
    try:
        response = requests.post(
            "http://localhost:8080/datasets/upload",
            files=files,
            timeout=60  # Give it time for LLM processing
        )
        
        print(f"Response status: {response.status_code}")
        print(f"Response headers: {response.headers}")
        
        if response.status_code == 200:
            try:
                data = response.json()
                print("✓ Upload successful!")
                print(f"Response: {data}")
            except:
                print("✗ Response is not valid JSON")
                print(f"Response text: {response.text}")
        else:
            print(f"✗ Upload failed with status {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.Timeout:
        print("✗ Request timed out")
    except Exception as e:
        print(f"✗ Error: {e}")

# List datasets to verify
print("\nFetching dataset list...")
try:
    response = requests.get("http://localhost:8080/datasets")
    if response.status_code == 200:
        data = response.json()
        print(f"✓ Found {len(data.get('datasets', []))} datasets")
        for ds in data.get('datasets', []):
            print(f"  - {ds.get('title', 'Untitled')}: {ds.get('file_name')}")
    else:
        print(f"✗ Failed to fetch datasets: {response.text}")
except Exception as e:
    print(f"✗ Error fetching datasets: {e}")
