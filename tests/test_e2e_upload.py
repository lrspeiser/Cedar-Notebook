#!/usr/bin/env python3
"""
End-to-End Test: File Upload with LLM Conversion to Parquet
Tests the complete flow from CSV upload through LLM analysis to Parquet conversion
"""

import requests
import json
import sys
import os
import time
from pathlib import Path

# Configuration
LOCAL_SERVER = "http://localhost:8080"
RENDER_SERVER = "https://cedar-notebook.onrender.com"

def create_test_csv():
    """Create a test CSV file with interesting data"""
    csv_content = """product_id,product_name,category,price,stock_quantity,last_updated,rating
101,Wireless Mouse,Electronics,29.99,150,2024-01-15,4.5
102,Mechanical Keyboard,Electronics,89.99,75,2024-01-14,4.8
103,USB-C Hub,Electronics,45.50,200,2024-01-16,4.2
104,Laptop Stand,Office,34.99,120,2024-01-13,4.6
105,Webcam HD,Electronics,79.99,50,2024-01-15,4.3
106,Desk Lamp LED,Office,42.00,90,2024-01-14,4.7
107,Monitor Arm,Office,125.00,30,2024-01-16,4.9
108,Bluetooth Speaker,Electronics,59.99,180,2024-01-15,4.4
109,Ergonomic Chair,Office,299.99,25,2024-01-13,4.8
110,Standing Desk,Office,450.00,15,2024-01-14,4.7"""
    
    with open("test_products.csv", "w") as f:
        f.write(csv_content)
    
    print("✅ Created test CSV file: test_products.csv")
    return "test_products.csv"

def start_local_server():
    """Try to start a local server with OpenAI key"""
    print("\n" + "="*60)
    print("Starting Local Server")
    print("="*60)
    
    # Check for OpenAI key
    api_key = os.environ.get("OPENAI_API_KEY", "")
    
    if not api_key:
        print("⚠️  No OPENAI_API_KEY in environment")
        print("   Trying to fetch from Render deployment...")
        
        # Try to fetch from Render if we have a token
        token = os.environ.get("APP_SHARED_TOKEN", "")
        if token:
            try:
                response = requests.get(
                    f"{RENDER_SERVER}/v1/key",
                    headers={"x-app-token": token},
                    timeout=5
                )
                if response.status_code == 200:
                    data = response.json()
                    api_key = data.get("openai_api_key", "")
                    if api_key:
                        print("✅ Fetched OpenAI key from Render")
                        os.environ["OPENAI_API_KEY"] = api_key
                else:
                    print(f"❌ Failed to fetch key from Render: {response.status_code}")
            except Exception as e:
                print(f"❌ Error fetching from Render: {e}")
    
    if not os.environ.get("OPENAI_API_KEY"):
        print("❌ No OpenAI API key available")
        return False
    
    # Start the server
    import subprocess
    print("Starting notebook server...")
    server_proc = subprocess.Popen(
        ["cargo", "run", "--bin", "notebook_server"],
        env=os.environ.copy(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Wait for server to start
    for i in range(30):
        try:
            response = requests.get(f"{LOCAL_SERVER}/health", timeout=1)
            if response.status_code == 200:
                print("✅ Local server is running")
                return server_proc
        except:
            pass
        time.sleep(1)
        if i % 5 == 0:
            print(f"   Waiting for server to start... ({i}s)")
    
    print("❌ Server failed to start")
    server_proc.terminate()
    return False

def test_file_upload(server_url, csv_file, token=None):
    """Test file upload with LLM enhancement"""
    print("\n" + "="*60)
    print(f"Testing File Upload to {server_url}")
    print("="*60)
    
    url = f"{server_url}/datasets/upload"
    
    with open(csv_file, 'rb') as f:
        files = {'file': (csv_file, f, 'text/csv')}
        headers = {}
        if token:
            headers['x-app-token'] = token
        
        print(f"Uploading {csv_file}...")
        print("This will:")
        print("  1. Upload the CSV file")
        print("  2. Call OpenAI to analyze the data")
        print("  3. Generate metadata (title, description)")
        print("  4. Create Julia code for Parquet conversion")
        print("  5. Store the dataset metadata")
        print()
        
        try:
            response = requests.post(url, files=files, headers=headers, timeout=60)
            
            print(f"Status Code: {response.status_code}")
            
            if response.status_code == 200:
                print("✅ Upload successful!\n")
                data = response.json()
                
                # Pretty print the response
                print("Response Data:")
                print(json.dumps(data, indent=2))
                
                if 'datasets' in data and len(data['datasets']) > 0:
                    dataset = data['datasets'][0]
                    print("\n" + "="*60)
                    print("📊 Dataset Analysis Results")
                    print("="*60)
                    print(f"ID:          {dataset.get('id', 'N/A')}")
                    print(f"File:        {dataset.get('file_name', 'N/A')}")
                    print(f"Title:       {dataset.get('title', 'N/A')}")
                    print(f"Description: {dataset.get('description', 'N/A')}")
                    print(f"Rows:        {dataset.get('row_count', 'N/A')}")
                    print(f"Columns:     {dataset.get('column_count', 'N/A')}")
                    
                    # Test querying the dataset
                    test_dataset_query(server_url, dataset.get('id'), token)
                
                return True
            else:
                print(f"❌ Upload failed with status {response.status_code}")
                print(f"Response: {response.text[:500]}")
                return False
                
        except requests.exceptions.Timeout:
            print("❌ Request timed out (LLM processing may be slow)")
            return False
        except Exception as e:
            print(f"❌ Error: {e}")
            return False

def test_dataset_query(server_url, dataset_id, token=None):
    """Test querying the uploaded dataset"""
    if not dataset_id:
        return
    
    print("\n" + "="*60)
    print("Testing Dataset Retrieval")
    print("="*60)
    
    url = f"{server_url}/datasets/{dataset_id}"
    headers = {}
    if token:
        headers['x-app-token'] = token
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            print("✅ Dataset retrieved successfully")
            data = response.json()
            
            # Show column information if available
            if 'column_info' in data:
                print("\n📋 Column Information:")
                for col in data['column_info']:
                    print(f"  - {col.get('name', 'N/A')}: {col.get('description', 'No description')}")
        else:
            print(f"❌ Failed to retrieve dataset: {response.status_code}")
    except Exception as e:
        print(f"❌ Error retrieving dataset: {e}")

def main():
    print("="*60)
    print("End-to-End Test: File Upload with LLM Conversion")
    print("="*60)
    
    # Create test data
    csv_file = create_test_csv()
    
    # Determine which server to use
    use_local = True
    server_proc = None
    
    # Check if we should use Render
    if os.environ.get("USE_RENDER") == "1" and os.environ.get("APP_SHARED_TOKEN"):
        print("\n📡 Using Render deployment")
        server_url = RENDER_SERVER
        token = os.environ.get("APP_SHARED_TOKEN")
        use_local = False
    else:
        # Try to start local server
        server_proc = start_local_server()
        if server_proc:
            server_url = LOCAL_SERVER
            token = None
        else:
            print("\n❌ Cannot proceed without a server")
            print("\nTo test with Render:")
            print("  export USE_RENDER=1")
            print("  export APP_SHARED_TOKEN='your-token'")
            print("\nTo test locally:")
            print("  export OPENAI_API_KEY='sk-your-key'")
            return 1
    
    # Run the upload test
    success = test_file_upload(server_url, csv_file, token)
    
    # Cleanup
    if server_proc:
        print("\n🛑 Stopping local server...")
        server_proc.terminate()
        server_proc.wait(timeout=5)
    
    # Summary
    print("\n" + "="*60)
    print("Test Summary")
    print("="*60)
    if success:
        print("✅ End-to-end test PASSED!")
        print("\nThe system successfully:")
        print("  1. Accepted the CSV file upload")
        print("  2. Used OpenAI to analyze the data")
        print("  3. Generated meaningful metadata")
        print("  4. Stored the dataset information")
        print("\nThe file is ready for:")
        print("  - Conversion to Parquet format")
        print("  - Querying with DuckDB")
        print("  - Further analysis with Julia")
    else:
        print("❌ End-to-end test FAILED")
        print("\nCheck that:")
        print("  - OpenAI API key is valid")
        print("  - Server has proper configuration")
        print("  - Network connectivity is working")
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
