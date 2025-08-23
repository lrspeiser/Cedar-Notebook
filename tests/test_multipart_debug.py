#!/usr/bin/env python3
"""
Debug multipart/form-data uploads to understand what's happening.
"""

import requests
import os

# Test file
test_file = "/Users/leonardspeiser/Desktop/sample_sales_data.csv"

if not os.path.exists(test_file):
    print(f"Test file not found: {test_file}")
    exit(1)

print("Testing different multipart upload methods...")
print("=" * 60)

# Method 1: Standard multipart with 'file' field (what curl uses)
print("\n1. Standard multipart with 'file' field:")
try:
    with open(test_file, 'rb') as f:
        files = {'file': (os.path.basename(test_file), f, 'text/csv')}
        response = requests.post('http://localhost:8080/datasets/upload', files=files)
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except Exception as e:
    print(f"   Error: {e}")

# Method 2: Multiple files with same field name
print("\n2. Multiple 'file' fields (simulating FormData.append multiple times):")
try:
    with open(test_file, 'rb') as f:
        # This simulates what happens when JS does formData.append('file', file) multiple times
        files = [('file', (os.path.basename(test_file), f, 'text/csv'))]
        response = requests.post('http://localhost:8080/datasets/upload', files=files)
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except Exception as e:
    print(f"   Error: {e}")

# Method 3: Without content type
print("\n3. Without explicit content type:")
try:
    with open(test_file, 'rb') as f:
        files = {'file': (os.path.basename(test_file), f)}
        response = requests.post('http://localhost:8080/datasets/upload', files=files)
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except Exception as e:
    print(f"   Error: {e}")

# Method 4: Raw multipart construction (what browsers actually do)
print("\n4. Manual multipart construction:")
try:
    import io
    from requests_toolbelt import MultipartEncoder
    
    with open(test_file, 'rb') as f:
        encoder = MultipartEncoder(
            fields={'file': (os.path.basename(test_file), f, 'text/csv')}
        )
        response = requests.post(
            'http://localhost:8080/datasets/upload',
            data=encoder,
            headers={'Content-Type': encoder.content_type}
        )
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except ImportError:
    print("   Skipped: requests_toolbelt not installed")
except Exception as e:
    print(f"   Error: {e}")

print("\n" + "=" * 60)
print("Testing what headers are being sent...")

# Check what headers curl sends vs what the browser might send
print("\n5. Checking headers with curl:")
import subprocess
result = subprocess.run([
    'curl', '-X', 'POST',
    'http://localhost:8080/datasets/upload',
    '-F', f'file=@{test_file}',
    '-v'
], capture_output=True, text=True)
# Extract Content-Type header from verbose output
for line in result.stderr.split('\n'):
    if 'Content-Type:' in line:
        print(f"   {line.strip()}")
        break

print("\nDone!")
