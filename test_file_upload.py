#!/usr/bin/env python3
"""
Test file upload functionality for Cedar backend.
Tests the /datasets/upload endpoint with various file types.
"""

import requests
import json
import os
import sys
from pathlib import Path

# Backend URL
BASE_URL = "http://localhost:8080"

def test_health():
    """Test if the backend server is running."""
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            print("✅ Backend server is running")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to backend server at http://localhost:8080")
        print("   Please start the server with: ./start_cedar_server.sh")
        return False

def create_test_file(filename, content):
    """Create a test file with specified content."""
    with open(filename, 'w') as f:
        f.write(content)
    return filename

def test_file_upload(file_path, file_type="text/csv"):
    """Test uploading a file to the backend."""
    print(f"\n📁 Testing upload of: {file_path}")
    print(f"   File type: {file_type}")
    
    if not os.path.exists(file_path):
        print(f"❌ File does not exist: {file_path}")
        return False
    
    file_size = os.path.getsize(file_path)
    print(f"   File size: {file_size} bytes")
    
    try:
        # Read file content
        with open(file_path, 'rb') as f:
            files = {
                'file': (os.path.basename(file_path), f, file_type)
            }
            
            # Send upload request
            print("   Sending upload request...")
            response = requests.post(
                f"{BASE_URL}/datasets/upload",
                files=files
            )
        
        print(f"   Response status: {response.status_code}")
        
        if response.status_code == 200:
            print("✅ Upload successful!")
            result = response.json()
            print(f"   Response: {json.dumps(result, indent=2)}")
            return True
        else:
            print(f"❌ Upload failed with status {response.status_code}")
            print(f"   Response: {response.text}")
            
            # Try to parse error details
            try:
                error_data = response.json()
                print(f"   Error details: {json.dumps(error_data, indent=2)}")
            except:
                print(f"   Raw response: {response.text[:500]}")
            
            return False
            
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Connection error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_multipart_upload(file_path):
    """Test uploading with explicit multipart form data."""
    print(f"\n📦 Testing multipart upload of: {file_path}")
    
    try:
        with open(file_path, 'r') as f:
            # Read first 30 lines for preview
            lines = []
            for i, line in enumerate(f):
                if i >= 30:
                    break
                lines.append(line)
            preview = ''.join(lines)
            
            # Reset to read full content
            f.seek(0)
            full_content = f.read()
        
        print(f"   Preview (first 30 lines):\n{preview[:500]}...")
        
        # Create multipart form data
        form_data = {
            'file_path': file_path,
            'file_name': os.path.basename(file_path),
            'file_size': str(os.path.getsize(file_path)),
            'file_type': 'text/csv',
            'preview': preview,
            'content': full_content
        }
        
        print("   Sending multipart request...")
        response = requests.post(
            f"{BASE_URL}/datasets/upload",
            data=form_data
        )
        
        print(f"   Response status: {response.status_code}")
        print(f"   Response: {response.text[:500]}")
        
        return response.status_code == 200
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

def test_json_upload(file_path):
    """Test uploading file data as JSON."""
    print(f"\n📋 Testing JSON upload of: {file_path}")
    
    try:
        with open(file_path, 'r') as f:
            # Read first 30 lines
            lines = []
            for i, line in enumerate(f):
                if i >= 30:
                    break
                lines.append(line)
            preview = ''.join(lines)
            
            # Reset and read full content
            f.seek(0)
            content = f.read()
        
        # Prepare JSON payload
        payload = {
            'file_path': file_path,
            'file_name': os.path.basename(file_path),
            'file_size': os.path.getsize(file_path),
            'file_type': 'text/csv',
            'preview': preview,
            'content': content
        }
        
        print(f"   Payload size: {len(json.dumps(payload))} bytes")
        print("   Sending JSON request...")
        
        response = requests.post(
            f"{BASE_URL}/datasets/upload",
            json=payload,
            headers={'Content-Type': 'application/json'}
        )
        
        print(f"   Response status: {response.status_code}")
        print(f"   Response: {response.text[:500]}")
        
        return response.status_code == 200
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

def main():
    """Run all file upload tests."""
    print("=" * 60)
    print("Cedar File Upload Test Suite")
    print("=" * 60)
    
    # Check server health
    if not test_health():
        sys.exit(1)
    
    # Create test files
    print("\n📝 Creating test files...")
    
    # Small CSV file
    csv_content = """name,age,city
Alice,30,New York
Bob,25,San Francisco
Charlie,35,Chicago
David,28,Boston
Eve,32,Seattle
Frank,29,Austin
Grace,31,Portland
Henry,27,Denver
Iris,33,Phoenix
Jack,26,Miami
Karen,34,Dallas
Leo,30,Atlanta
Maya,28,Houston
Noah,32,Philadelphia
Olivia,29,San Diego
Peter,31,Las Vegas
Quinn,27,Nashville
Rachel,33,Detroit
Sam,26,Minneapolis
Tara,34,New Orleans
Uma,30,Salt Lake City
Victor,28,Kansas City
Wendy,32,Indianapolis
Xavier,29,Columbus
Yara,31,Charlotte
Zoe,27,Milwaukee
Aaron,33,Baltimore
Bella,26,Memphis
Carlos,34,Louisville
Diana,30,Portland"""
    
    csv_file = create_test_file("test_data.csv", csv_content)
    
    # JSON file
    json_content = json.dumps({
        "dataset": "test",
        "records": [
            {"id": 1, "value": "alpha"},
            {"id": 2, "value": "beta"},
            {"id": 3, "value": "gamma"}
        ]
    }, indent=2)
    json_file = create_test_file("test_data.json", json_content)
    
    # Text file
    text_content = "\n".join([f"Line {i}: This is test data for line number {i}" for i in range(1, 51)])
    text_file = create_test_file("test_data.txt", text_content)
    
    print("✅ Test files created")
    
    # Run tests
    print("\n" + "=" * 60)
    print("Running Upload Tests")
    print("=" * 60)
    
    # Test 1: Standard file upload with multipart/form-data
    print("\n1️⃣  Standard File Upload (multipart/form-data)")
    test_file_upload(csv_file, "text/csv")
    
    # Test 2: JSON file upload
    print("\n2️⃣  JSON File Upload")
    test_file_upload(json_file, "application/json")
    
    # Test 3: Text file upload
    print("\n3️⃣  Text File Upload")
    test_file_upload(text_file, "text/plain")
    
    # Test 4: Alternative multipart upload
    print("\n4️⃣  Alternative Multipart Upload")
    test_multipart_upload(csv_file)
    
    # Test 5: JSON payload upload
    print("\n5️⃣  JSON Payload Upload")
    test_json_upload(csv_file)
    
    # Clean up test files
    print("\n🧹 Cleaning up test files...")
    for f in [csv_file, json_file, text_file]:
        if os.path.exists(f):
            os.remove(f)
            print(f"   Removed: {f}")
    
    print("\n" + "=" * 60)
    print("Test suite completed!")
    print("=" * 60)

if __name__ == "__main__":
    main()
