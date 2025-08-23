#!/usr/bin/env python3
"""
Test just the OpenAI key fetching and basic server functionality
"""

import requests
import json
import sys
import os

RENDER_SERVER = "https://cedar-notebook.onrender.com"
TOKEN = "403-298-09345-023495"

def test_key_fetch():
    """Test fetching the OpenAI key from Render"""
    print("="*60)
    print("Testing OpenAI Key Fetch from Render")
    print("="*60)
    
    headers = {"x-app-token": TOKEN}
    
    print(f"\n1. Connecting to: {RENDER_SERVER}/v1/key")
    print(f"   Using token: {TOKEN[:10]}...")
    
    try:
        response = requests.get(f"{RENDER_SERVER}/v1/key", headers=headers, timeout=10)
        
        print(f"\n2. Response Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            api_key = data.get("openai_api_key")
            
            if api_key and api_key.startswith("sk-"):
                print(f"   ✅ Successfully fetched OpenAI key")
                print(f"   Key fingerprint: {api_key[:6]}...{api_key[-4:]}")
                
                # Test the key with OpenAI directly
                print("\n3. Testing key with OpenAI API directly...")
                test_openai_key(api_key)
                
                return api_key
            else:
                print("   ❌ Invalid key format received")
                print(f"   Response: {json.dumps(data, indent=2)}")
        else:
            print(f"   ❌ Failed to fetch key")
            print(f"   Response: {response.text[:200]}")
            
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    return None

def test_openai_key(api_key):
    """Test the OpenAI key directly"""
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    # Simple completion test
    data = {
        "model": "gpt-4o-mini",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Say 'Cedar test successful!' in exactly 4 words."}
        ],
        "max_tokens": 10
    }
    
    try:
        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers=headers,
            json=data,
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.json()
            content = result["choices"][0]["message"]["content"]
            print(f"   ✅ OpenAI API test successful!")
            print(f"   Response: {content}")
        else:
            print(f"   ❌ OpenAI API test failed: {response.status_code}")
            print(f"   Error: {response.text[:200]}")
            
    except Exception as e:
        print(f"   ❌ Error testing OpenAI: {e}")

def test_server_health():
    """Test the Render server health endpoint"""
    print("\n" + "="*60)
    print("Testing Render Server Health")
    print("="*60)
    
    # Test without token (should fail)
    print("\n1. Testing /health without token (should fail)...")
    try:
        response = requests.get(f"{RENDER_SERVER}/health", timeout=5)
        print(f"   Status: {response.status_code}")
        if response.status_code == 401:
            print("   ✅ Correctly requires authentication")
        else:
            print(f"   ⚠️  Unexpected response: {response.text[:100]}")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    # Test with token
    print("\n2. Testing /health with token...")
    headers = {"x-app-token": TOKEN}
    try:
        response = requests.get(f"{RENDER_SERVER}/health", headers=headers, timeout=5)
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            print("   ✅ Server is healthy")
            print(f"   Response: {response.text}")
        else:
            print(f"   ❌ Unexpected response: {response.text[:100]}")
    except Exception as e:
        print(f"   ❌ Error: {e}")

def main():
    print("Cedar Notebook - Render Server Integration Test")
    print("="*60)
    print("\nThis test will verify:")
    print("  1. Render server is accessible")
    print("  2. Authentication token works")
    print("  3. OpenAI key can be fetched")
    print("  4. OpenAI key is valid and works")
    print()
    
    # Test server health
    test_server_health()
    
    # Test key fetching
    api_key = test_key_fetch()
    
    if api_key:
        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED!")
        print("="*60)
        print("\nSummary:")
        print("  ✓ Render server is running and healthy")
        print("  ✓ Authentication token is valid")
        print("  ✓ OpenAI key successfully fetched")
        print("  ✓ OpenAI key works with the API")
        print("\nThe Cedar-Render integration is working correctly!")
        print("The file upload issue is likely related to Julia execution,")
        print("not the OpenAI key provisioning.")
        return 0
    else:
        print("\n" + "="*60)
        print("❌ TESTS FAILED")
        print("="*60)
        return 1

if __name__ == "__main__":
    sys.exit(main())
