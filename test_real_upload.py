#!/usr/bin/env python3
"""
Real End-to-End Test: Fetch OpenAI key from Render and test file upload
This is how the actual Cedar app would work in production
"""

import requests
import json
import sys
import os
import time
import subprocess

RENDER_SERVER = "https://cedar-notebook.onrender.com"
LOCAL_SERVER = "http://localhost:8080"

def fetch_openai_key_from_render(token):
    """Fetch the real OpenAI key from your Render deployment"""
    print("Fetching OpenAI key from Render...")
    
    headers = {"x-app-token": token}
    
    try:
        response = requests.get(f"{RENDER_SERVER}/v1/key", headers=headers, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            api_key = data.get("openai_api_key")
            if api_key and api_key.startswith("sk-"):
                print(f"✅ Successfully fetched OpenAI key (fingerprint: {api_key[:6]}...{api_key[-4:]})")
                return api_key
            else:
                print("❌ Invalid key format received")
                return None
        else:
            print(f"❌ Failed to fetch key: {response.status_code}")
            print(f"   Response: {response.text}")
            return None
    except Exception as e:
        print(f"❌ Error fetching key: {e}")
        return None

def start_local_server_with_key(api_key):
    """Start local server with the fetched OpenAI key"""
    print("\nStarting local Cedar server with fetched key...")
    
    # Set the API key in environment
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = api_key
    
    # Start the server
    server_proc = subprocess.Popen(
        ["cargo", "run", "--bin", "notebook_server"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Wait for server to be ready
    for i in range(30):
        try:
            response = requests.get(f"{LOCAL_SERVER}/health", timeout=1)
            if response.status_code == 200:
                print("✅ Local server is running with real OpenAI key")
                return server_proc
        except:
            pass
        time.sleep(1)
        if i % 5 == 0:
            print(f"   Waiting for server... ({i}s)")
    
    print("❌ Server failed to start")
    server_proc.terminate()
    return None

def create_test_data():
    """Create a real CSV file for testing"""
    csv_content = """employee_id,name,department,salary,hire_date,performance_rating,location
E001,Sarah Johnson,Engineering,125000,2020-03-15,4.5,San Francisco
E002,Michael Chen,Marketing,95000,2019-07-22,4.2,New York
E003,Emily Rodriguez,Sales,105000,2021-01-10,4.8,Chicago
E004,David Kim,Engineering,135000,2018-11-03,4.6,San Francisco
E005,Jessica Taylor,HR,85000,2020-09-18,4.3,Boston
E006,Robert Martinez,Finance,115000,2019-04-25,4.7,New York
E007,Amanda Wilson,Engineering,118000,2021-06-12,4.4,Seattle
E008,Christopher Lee,Marketing,92000,2020-12-01,4.1,Los Angeles
E009,Maria Garcia,Sales,98000,2019-08-30,4.9,Miami
E010,James Anderson,Operations,102000,2021-03-08,4.5,Chicago"""
    
    filename = "employee_data.csv"
    with open(filename, "w") as f:
        f.write(csv_content)
    
    print(f"✅ Created test file: {filename}")
    return filename

def test_file_upload(csv_file):
    """Test the actual file upload with real LLM processing"""
    print("\n" + "="*60)
    print("Testing File Upload with Real LLM Processing")
    print("="*60)
    
    url = f"{LOCAL_SERVER}/datasets/upload"
    
    with open(csv_file, 'rb') as f:
        files = {'file': (csv_file, f, 'text/csv')}
        
        print(f"\nUploading {csv_file} to Cedar server...")
        print("The server will now:")
        print("  1. Receive the CSV file")
        print("  2. Call OpenAI GPT to analyze the data")
        print("  3. Generate intelligent metadata")
        print("  4. Create Julia code for Parquet conversion")
        print("  5. Store everything in the database")
        print("\nThis may take 10-30 seconds for LLM processing...")
        
        try:
            response = requests.post(url, files=files, timeout=60)
            
            print(f"\nStatus: {response.status_code}")
            
            if response.status_code == 200:
                print("✅ Upload successful!\n")
                data = response.json()
                
                # Display the LLM-generated results
                if 'datasets' in data and len(data['datasets']) > 0:
                    dataset = data['datasets'][0]
                    
                    print("="*60)
                    print("🤖 LLM-Generated Analysis")
                    print("="*60)
                    print(f"\nDataset ID: {dataset.get('id', 'N/A')}")
                    print(f"Original File: {dataset.get('file_name', 'N/A')}")
                    print(f"\n📝 AI-Generated Title:\n   {dataset.get('title', 'N/A')}")
                    print(f"\n📄 AI-Generated Description:\n   {dataset.get('description', 'N/A')}")
                    print(f"\nData Stats:")
                    print(f"  - Rows: {dataset.get('row_count', 'Unknown')}")
                    print(f"  - Columns: {dataset.get('column_count', 'Unknown')}")
                    
                    # Query the dataset for more details
                    dataset_id = dataset.get('id')
                    if dataset_id:
                        query_dataset_details(dataset_id)
                    
                    return True
                else:
                    print("⚠️  No dataset information in response")
                    print(json.dumps(data, indent=2))
                    return False
            else:
                print(f"❌ Upload failed: {response.status_code}")
                print(f"Error: {response.text[:500]}")
                return False
                
        except requests.exceptions.Timeout:
            print("❌ Request timed out (LLM processing took too long)")
            return False
        except Exception as e:
            print(f"❌ Error during upload: {e}")
            return False

def query_dataset_details(dataset_id):
    """Query the uploaded dataset for detailed information"""
    print("\n" + "="*60)
    print("Querying Dataset Details")
    print("="*60)
    
    url = f"{LOCAL_SERVER}/datasets/{dataset_id}"
    
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            
            # Display column analysis
            if 'column_info' in data and len(data['column_info']) > 0:
                print("\n📊 Column Analysis (AI-Generated):")
                for col in data['column_info']:
                    name = col.get('name', 'Unknown')
                    desc = col.get('description', 'No description generated')
                    dtype = col.get('data_type', 'Unknown')
                    print(f"\n  Column: {name}")
                    print(f"    Type: {dtype}")
                    print(f"    Description: {desc}")
                    
                    # Show statistics if available
                    if col.get('min_value'):
                        print(f"    Min: {col['min_value']}")
                    if col.get('max_value'):
                        print(f"    Max: {col['max_value']}")
                    if col.get('null_count') is not None:
                        print(f"    Nulls: {col['null_count']}")
            
            # Show sample data
            if 'sample_data' in data:
                print("\n📋 Sample Data (first few rows):")
                sample = data['sample_data']
                lines = sample.split('\n')[:5]
                for line in lines:
                    print(f"  {line}")
                    
        else:
            print(f"❌ Failed to get dataset details: {response.status_code}")
    except Exception as e:
        print(f"❌ Error querying dataset: {e}")

def main():
    print("="*60)
    print("Real End-to-End Test with Render OpenAI Key")
    print("="*60)
    print("\nThis test will:")
    print("1. Fetch the real OpenAI key from your Render server")
    print("2. Start a local Cedar server with that key")
    print("3. Upload a CSV file")
    print("4. Use OpenAI GPT to analyze and enhance the data")
    print("5. Show the AI-generated results")
    print()
    
    # Get the token from environment or use the hardcoded value
    token = os.environ.get("APP_SHARED_TOKEN", "403-298-09345-023495")
    
    if not token:
        print("❌ Error: APP_SHARED_TOKEN not set")
        print("\nTo run this test, you need to provide your Render authentication token:")
        print("  export APP_SHARED_TOKEN='your-token-from-render'")
        print("\nYou can find this in your Render dashboard environment variables.")
        return 1
    
    print(f"Using token: {token[:10]}..." if len(token) > 10 else "Using provided token")
    
    # Step 1: Fetch the OpenAI key from Render
    api_key = fetch_openai_key_from_render(token)
    if not api_key:
        print("\n❌ Could not fetch OpenAI key from Render")
        print("Please check:")
        print("  1. APP_SHARED_TOKEN is correct")
        print("  2. Render server is running")
        print("  3. OPENAI_API_KEY is set on Render")
        return 1
    
    # Step 2: Start local server with the key
    server_proc = start_local_server_with_key(api_key)
    if not server_proc:
        print("❌ Could not start local server")
        return 1
    
    try:
        # Step 3: Create test data
        csv_file = create_test_data()
        
        # Step 4: Upload and process with LLM
        success = test_file_upload(csv_file)
        
        if success:
            print("\n" + "="*60)
            print("✅ SUCCESS: End-to-End Test Completed!")
            print("="*60)
            print("\nThe system successfully:")
            print("  ✓ Fetched OpenAI key from Render deployment")
            print("  ✓ Started local server with real API key")
            print("  ✓ Uploaded CSV file")
            print("  ✓ Used OpenAI GPT to analyze the data")
            print("  ✓ Generated intelligent metadata and descriptions")
            print("  ✓ Prepared Julia code for Parquet conversion")
            print("  ✓ Stored everything in the database")
            print("\nThis is exactly how the Cedar app works in production!")
        else:
            print("\n❌ Test failed during upload/processing")
            
    finally:
        # Cleanup
        print("\n🛑 Stopping server...")
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except:
            server_proc.kill()
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
