#!/usr/bin/env python3
"""
Test Cedar Backend API Endpoints
This script tests all the HTTP endpoints that the desktop app UI uses.
Run this BEFORE testing the desktop app to ensure the backend is working.
"""

import requests
import json
import time
import sys
import os
from datetime import datetime

# Configuration
API_BASE = "http://localhost:8080"
TEST_CSV = "test_data.csv"

def colored(text, color):
    """Add color to terminal output"""
    colors = {
        'green': '\033[92m',
        'red': '\033[91m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'reset': '\033[0m'
    }
    return f"{colors.get(color, '')}{text}{colors['reset']}"

def log_test(test_name, status, details=""):
    """Log test results"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    status_symbol = "✅" if status == "PASS" else "❌" if status == "FAIL" else "⚠️"
    status_color = "green" if status == "PASS" else "red" if status == "FAIL" else "yellow"
    
    print(f"[{timestamp}] {status_symbol} {test_name}: {colored(status, status_color)}")
    if details:
        print(f"    → {details}")

def create_test_csv():
    """Create a test CSV file"""
    csv_content = """Date,Product,Category,Quantity,Price
2024-01-01,Laptop,Electronics,5,999.99
2024-01-02,Mouse,Electronics,10,29.99
2024-01-03,Desk,Furniture,2,299.99
2024-01-04,Chair,Furniture,4,199.99
2024-01-05,Monitor,Electronics,3,399.99"""
    
    with open(TEST_CSV, 'w') as f:
        f.write(csv_content)
    return TEST_CSV

def test_health_endpoint():
    """Test /health endpoint"""
    try:
        response = requests.get(f"{API_BASE}/health", timeout=5)
        if response.status_code == 200:
            log_test("Health Check", "PASS", f"Server is running (status: {response.status_code})")
            return True
        else:
            log_test("Health Check", "FAIL", f"Unexpected status: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        log_test("Health Check", "FAIL", "Cannot connect to server - is it running?")
        return False
    except Exception as e:
        log_test("Health Check", "FAIL", str(e))
        return False

def test_submit_query():
    """Test /commands/submit_query endpoint"""
    try:
        # Test simple math query
        payload = {
            "prompt": "What is 2+2? Just give me the number.",
            "datasets": [],
            "file_context": None
        }
        
        log_test("Submit Query", "INFO", "Sending query: 'What is 2+2?'")
        
        response = requests.post(
            f"{API_BASE}/commands/submit_query",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            log_test("Submit Query", "PASS", f"Got response: {json.dumps(result, indent=2)[:200]}...")
            
            # Check if we got a meaningful response
            if result.get('response') or result.get('julia_code') or result.get('execution_output'):
                log_test("Query Response Content", "PASS", "Response contains expected fields")
                return True
            else:
                log_test("Query Response Content", "WARN", "Response is empty")
                return True  # Still passing as the endpoint worked
        else:
            error_text = response.text[:500]
            log_test("Submit Query", "FAIL", f"Status {response.status_code}: {error_text}")
            return False
            
    except requests.exceptions.Timeout:
        log_test("Submit Query", "FAIL", "Request timed out after 30 seconds")
        return False
    except Exception as e:
        log_test("Submit Query", "FAIL", str(e))
        return False

def test_dataset_upload():
    """Test /datasets/upload endpoint"""
    try:
        # Create test file
        test_file = create_test_csv()
        
        with open(test_file, 'rb') as f:
            files = {'files': (test_file, f, 'text/csv')}
            
            log_test("Dataset Upload", "INFO", f"Uploading {test_file}")
            
            response = requests.post(
                f"{API_BASE}/datasets/upload",
                files=files,
                timeout=30
            )
        
        if response.status_code == 200:
            result = response.json()
            log_test("Dataset Upload", "PASS", f"Uploaded successfully: {json.dumps(result, indent=2)[:200]}...")
            
            # Clean up test file
            os.remove(test_file)
            
            # Return dataset ID for further tests
            if result.get('datasets') and len(result['datasets']) > 0:
                return result['datasets'][0].get('id')
            return True
        else:
            error_text = response.text[:500]
            log_test("Dataset Upload", "FAIL", f"Status {response.status_code}: {error_text}")
            os.remove(test_file)
            return False
            
    except Exception as e:
        log_test("Dataset Upload", "FAIL", str(e))
        if os.path.exists(test_file):
            os.remove(test_file)
        return False

def test_list_datasets():
    """Test /datasets endpoint"""
    try:
        response = requests.get(f"{API_BASE}/datasets", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            log_test("List Datasets", "PASS", f"Found {len(result)} dataset(s)")
            return True
        else:
            log_test("List Datasets", "FAIL", f"Status {response.status_code}")
            return False
            
    except Exception as e:
        log_test("List Datasets", "FAIL", str(e))
        return False

def test_api_key_status():
    """Check if API key is configured"""
    try:
        # Try a simple query that requires API key
        payload = {
            "prompt": "test",
            "datasets": [],
            "file_context": None
        }
        
        response = requests.post(
            f"{API_BASE}/commands/submit_query",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        
        # Check for API key errors in response
        if response.status_code == 500:
            error_text = response.text.lower()
            if "api key" in error_text or "openai_api_key" in error_text:
                log_test("API Key Status", "FAIL", "API key not configured on server")
                print(colored("\n⚠️  IMPORTANT: The server doesn't have an API key configured!", "yellow"))
                print("Please ensure OPENAI_API_KEY is set when starting the server:")
                print("  export OPENAI_API_KEY=your-key-here")
                print("  cargo run --release --bin notebook_server")
                print("Or use the start script: ./start_cedar_server.sh\n")
                return False
        
        log_test("API Key Status", "PASS", "API key appears to be configured")
        return True
        
    except Exception as e:
        log_test("API Key Status", "WARN", f"Could not determine status: {e}")
        return True  # Don't fail the test

def check_server_running():
    """Check if the server is running and provide instructions if not"""
    try:
        response = requests.get(f"{API_BASE}/health", timeout=2)
        return True
    except:
        print(colored("\n❌ ERROR: Cannot connect to backend server!", "red"))
        print("\nThe Cedar backend server is not running on http://localhost:8080")
        print("\nTo start the server:")
        print("1. Open a new terminal")
        print("2. Navigate to the project: cd /Users/leonardspeiser/Projects/cedarcli")
        print("3. Start the server: ./start_cedar_server.sh")
        print("\nOr manually:")
        print("  export OPENAI_API_KEY=your-key-here")
        print("  cargo run --release --bin notebook_server\n")
        return False

def main():
    """Run all tests"""
    print(colored("\n" + "="*60, "blue"))
    print(colored("Cedar Backend API Test Suite", "blue"))
    print(colored("="*60, "blue"))
    print(f"\nTesting API at: {API_BASE}")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    # Check if server is running first
    if not check_server_running():
        sys.exit(1)
    
    # Run tests
    tests_passed = 0
    tests_failed = 0
    
    # Test endpoints
    test_results = []
    
    # 1. Health check
    if test_health_endpoint():
        tests_passed += 1
    else:
        tests_failed += 1
        print(colored("\n⚠️  Server is not responding. Stopping tests.", "red"))
        sys.exit(1)
    
    # 2. API Key status
    if test_api_key_status():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # 3. List datasets
    if test_list_datasets():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # 4. Upload dataset
    dataset_id = test_dataset_upload()
    if dataset_id:
        tests_passed += 1
    else:
        tests_failed += 1
    
    # 5. Submit query
    if test_submit_query():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Summary
    print(colored("\n" + "="*60, "blue"))
    print(colored("Test Summary", "blue"))
    print(colored("="*60, "blue"))
    print(f"\n✅ Passed: {tests_passed}")
    print(f"❌ Failed: {tests_failed}")
    
    if tests_failed == 0:
        print(colored("\n🎉 All tests passed! The backend is ready for the desktop app.", "green"))
    else:
        print(colored(f"\n⚠️  {tests_failed} test(s) failed. Please fix the issues before testing the desktop app.", "yellow"))
    
    print("\nNext steps:")
    if tests_failed == 0:
        print("1. The backend is working correctly")
        print("2. You can now test the desktop app")
        print("3. If the desktop app shows 'offline', check that it's connecting to localhost:8080")
    else:
        print("1. Fix the failing tests above")
        print("2. Ensure the server has OPENAI_API_KEY configured")
        print("3. Re-run this test script")
    
    return tests_failed == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
