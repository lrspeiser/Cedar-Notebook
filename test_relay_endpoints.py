#!/usr/bin/env python3
"""
Test the different endpoints on the cedar-notebook.onrender.com relay
"""

import requests
import json

RELAY_URL = "https://cedar-notebook.onrender.com"
APP_TOKEN = "403-298-09345-023495"

def test_endpoint(endpoint, method="POST", data=None):
    """Test if an endpoint exists on the relay"""
    url = f"{RELAY_URL}{endpoint}"
    headers = {
        "x-app-token": APP_TOKEN,
        "Content-Type": "application/json"
    }
    
    print(f"\nTesting {method} {url}")
    print("-" * 50)
    
    try:
        if method == "POST":
            if data:
                response = requests.post(url, headers=headers, json=data, timeout=10)
            else:
                response = requests.post(url, headers=headers, timeout=10)
        else:
            response = requests.get(url, headers=headers, timeout=10)
        
        print(f"Status Code: {response.status_code}")
        
        # Show first 500 chars of response
        if response.text:
            preview = response.text[:500]
            if len(response.text) > 500:
                preview += "..."
            print(f"Response: {preview}")
        
        return response.status_code
        
    except Exception as e:
        print(f"Error: {e}")
        return None

# Test different endpoints
print("=" * 60)
print("Testing Cedar Notebook Relay Endpoints")
print("=" * 60)

# Test the key endpoint (we know this works)
print("\n1. Testing /v1/key endpoint (should work)")
test_endpoint("/v1/key", "POST")

# Test the GPT-5 responses endpoint
print("\n2. Testing /v1/responses endpoint (GPT-5)")
test_data = {
    "model": "gpt-5",
    "input": "Hello, world!",
    "text": {
        "format": {
            "type": "json_object"
        }
    }
}
test_endpoint("/v1/responses", "POST", test_data)

# Test the standard chat completions endpoint
print("\n3. Testing /v1/chat/completions endpoint (standard OpenAI)")
test_data = {
    "model": "gpt-4o-mini",
    "messages": [
        {"role": "user", "content": "Hello, world!"}
    ]
}
test_endpoint("/v1/chat/completions", "POST", test_data)

# Test root endpoint to see what's available
print("\n4. Testing root endpoint")
test_endpoint("/", "GET")

# Test /v1 endpoint
print("\n5. Testing /v1 endpoint")
test_endpoint("/v1", "GET")

print("\n" + "=" * 60)
print("Summary:")
print("-" * 60)
print("The relay server at cedar-notebook.onrender.com:")
print("- Supports /v1/key for API key fetching")
print("- May or may not support /v1/responses (GPT-5)")
print("- May or may not support /v1/chat/completions (standard)")
print("\nBased on these results, we can determine which endpoints")
print("the relay actually supports and update the code accordingly.")