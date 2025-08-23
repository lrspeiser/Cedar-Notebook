#!/usr/bin/env python3
"""
Full pipeline test for Cedar system.
Tests both simple arithmetic and complete file processing.
"""

import requests
import json
import time
import os
import tempfile
from pathlib import Path

# Configuration
SERVER_URL = "http://localhost:8080"
API_KEY = os.getenv("OPENAI_API_KEY", "")

def test_simple_arithmetic():
    """Test 1: Simple 2+2 calculation"""
    print("\n" + "="*60)
    print("TEST 1: Simple Arithmetic (2+2)")
    print("="*60)
    
    payload = {
        "prompt": "What is 2 + 2?",
        "api_key": API_KEY
    }
    
    print("Sending query: 'What is 2 + 2?'")
    response = requests.post(
        f"{SERVER_URL}/commands/submit_query",
        json=payload,
        timeout=30
    )
    
    if response.status_code == 200:
        result = response.json()
        print(f"✅ Query submitted successfully!")
        print(f"   Run ID: {result.get('run_id')}")
        print(f"   Response: {result.get('response', 'Processing...')}")
        
        # Wait for processing
        time.sleep(3)
        
        # Check for Julia code
        if result.get('julia_code'):
            print(f"\n📝 Generated Julia code:")
            print("   " + result['julia_code'].replace('\n', '\n   '))
        
        # Check execution output
        if result.get('execution_output'):
            print(f"\n📊 Execution output:")
            print(f"   {result['execution_output']}")
            
        return True
    else:
        print(f"❌ Failed: Status {response.status_code}")
        print(f"   Error: {response.text}")
        return False

def test_csv_file_processing():
    """Test 2: Process a CSV file and create Parquet/DuckDB"""
    print("\n" + "="*60)
    print("TEST 2: CSV File Processing Pipeline")
    print("="*60)
    
    # Create a test CSV file
    csv_content = """name,age,department,salary,hire_date
Alice Johnson,32,Engineering,95000,2019-03-15
Bob Smith,28,Marketing,72000,2020-07-22
Carol Williams,45,Engineering,115000,2015-11-08
David Brown,38,Sales,88000,2018-05-20
Eve Davis,29,Marketing,70000,2021-01-10
Frank Miller,52,Engineering,125000,2010-09-30
Grace Wilson,35,HR,85000,2017-04-12
Henry Moore,41,Sales,92000,2016-08-25
Iris Taylor,27,Engineering,82000,2022-02-14
Jack Anderson,39,Marketing,78000,2019-10-05"""
    
    # Save to a temporary file
    temp_dir = tempfile.mkdtemp()
    csv_path = os.path.join(temp_dir, "employees.csv")
    
    with open(csv_path, 'w') as f:
        f.write(csv_content)
    
    print(f"📁 Created test CSV file: {csv_path}")
    print(f"   Size: {os.path.getsize(csv_path)} bytes")
    print(f"   Preview of data:")
    print("   " + csv_content.split('\n')[0])  # Header
    print("   " + csv_content.split('\n')[1])  # First row
    print("   ...")
    
    # Send file for processing
    payload = {
        "file_info": {
            "name": "employees.csv",
            "path": csv_path,
            "size": os.path.getsize(csv_path),
            "file_type": "text/csv",
            "preview": csv_content
        },
        "api_key": API_KEY
    }
    
    print(f"\n📤 Sending file for processing...")
    response = requests.post(
        f"{SERVER_URL}/commands/submit_query",
        json=payload,
        timeout=60
    )
    
    if response.status_code == 200:
        result = response.json()
        print(f"✅ File submitted successfully!")
        print(f"   Run ID: {result.get('run_id')}")
        
        # Wait for processing
        print("\n⏳ Processing file (this may take 10-30 seconds)...")
        time.sleep(15)
        
        # Check if Parquet file was created
        parquet_dir = Path("data/parquet")
        if parquet_dir.exists():
            parquet_files = list(parquet_dir.glob("*.parquet"))
            if parquet_files:
                print(f"\n✅ Parquet files created:")
                for pf in parquet_files[-3:]:  # Show last 3
                    print(f"   - {pf.name} ({pf.stat().st_size} bytes)")
        
        # Check DuckDB metadata
        metadata_db = Path("runs/metadata.duckdb")
        if metadata_db.exists():
            print(f"\n✅ DuckDB metadata database exists:")
            print(f"   - {metadata_db} ({metadata_db.stat().st_size} bytes)")
        
        # Try to list datasets
        print("\n📊 Checking available datasets...")
        datasets_response = requests.get(f"{SERVER_URL}/datasets")
        if datasets_response.status_code == 200:
            data = datasets_response.json()
            # Handle both formats: list or object with 'datasets' key
            if isinstance(data, dict) and 'datasets' in data:
                datasets = data['datasets']
            elif isinstance(data, list):
                datasets = data
            else:
                datasets = []
                
            if datasets:
                print(f"✅ Found {len(datasets)} datasets:")
                for ds in datasets[:3]:  # Show first 3
                    print(f"   - {ds.get('title', ds.get('filename', 'Unknown'))}")
            else:
                print("   No datasets found yet (may still be processing)")
        
        # Show execution details
        if result.get('julia_code'):
            print(f"\n📝 Generated Julia code preview:")
            lines = result['julia_code'].split('\n')[:10]
            for line in lines:
                print(f"   {line}")
            if len(result['julia_code'].split('\n')) > 10:
                print("   ...")
                
        if result.get('execution_output'):
            print(f"\n📊 Execution output preview:")
            lines = str(result['execution_output']).split('\n')[:10]
            for line in lines:
                print(f"   {line}")
                
        # Clean up
        os.unlink(csv_path)
        os.rmdir(temp_dir)
        
        return True
    else:
        print(f"❌ Failed: Status {response.status_code}")
        print(f"   Error: {response.text}")
        return False

def main():
    """Run full pipeline tests"""
    print("\n" + "🌲"*30)
    print("CEDAR FULL PIPELINE TEST")
    print("🌲"*30)
    
    # Check server health
    print("\n🔍 Checking server status...")
    try:
        health = requests.get(f"{SERVER_URL}/health", timeout=2)
        if health.status_code == 200:
            print("✅ Server is healthy")
        else:
            print("❌ Server is not healthy")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to server: {e}")
        print("Please start the server with: ./scripts/start_cedar_server.sh")
        return False
    
    # Check API key
    if not API_KEY:
        print("\n⚠️  Warning: No OPENAI_API_KEY set")
        print("Some tests may fail. Set with: export OPENAI_API_KEY='sk-...'")
    else:
        print(f"✅ API key configured ({API_KEY[:7]}...)")
    
    # Run tests
    results = []
    
    # Test 1: Simple arithmetic
    results.append(("Simple Arithmetic (2+2)", test_simple_arithmetic()))
    
    # Test 2: CSV file processing
    results.append(("CSV File Processing", test_csv_file_processing()))
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    for test_name, passed in results:
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"{test_name}: {status}")
    
    all_passed = all(r[1] for r in results)
    
    print("\n" + "="*60)
    if all_passed:
        print("🎉 ALL TESTS PASSED!")
    else:
        print("⚠️  SOME TESTS FAILED")
    print("="*60)
    
    # Show data directory contents
    print("\n📁 Data Directory Contents:")
    data_dir = Path("data")
    if data_dir.exists():
        for item in data_dir.rglob("*"):
            if item.is_file() and not item.name.startswith('.'):
                rel_path = item.relative_to(data_dir)
                size = item.stat().st_size
                print(f"   {rel_path} ({size:,} bytes)")
    
    return all_passed

if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)
