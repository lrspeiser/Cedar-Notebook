#!/usr/bin/env python3
"""
Test fetching OpenAI key from Cedar server on Render
This demonstrates how the Cedar app can get the API key from the deployed server
"""

import requests
import json
import os
import sys

# Server configuration
CEDAR_SERVER_URL = "https://cedar-notebook.onrender.com"
APP_TOKEN = os.environ.get("APP_SHARED_TOKEN", "")

def fetch_openai_key():
    """Fetch OpenAI key from the Cedar server on Render"""
    
    if not APP_TOKEN:
        print("❌ Error: APP_SHARED_TOKEN environment variable is not set")
        print("\nTo use the Render server, you need to set the shared token:")
        print("  export APP_SHARED_TOKEN='your-shared-token-here'")
        print("\nThis token should match what's configured on Render.")
        return None
    
    url = f"{CEDAR_SERVER_URL}/config/openai_key"
    headers = {
        "x-app-token": APP_TOKEN
    }
    
    print(f"Fetching OpenAI key from: {url}")
    print(f"Using token: {APP_TOKEN[:10]}..." if len(APP_TOKEN) > 10 else "Using token: ***")
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            api_key = data.get("openai_api_key")
            
            if api_key:
                print("✅ Successfully fetched OpenAI key from server!")
                print(f"   Key fingerprint: {api_key[:6]}...{api_key[-4:]}")
                print(f"   Source: {data.get('source', 'unknown')}")
                return api_key
            else:
                print("❌ Server response missing API key")
                print(f"   Response: {json.dumps(data, indent=2)}")
        elif response.status_code == 401:
            print("❌ Authentication failed (401)")
            print("   Check that APP_SHARED_TOKEN matches the server configuration")
        elif response.status_code == 404:
            print("❌ Endpoint not found (404)")
            print("   The /config/openai_key endpoint may not be deployed yet")
        elif response.status_code == 500:
            print("❌ Server error (500)")
            print(f"   Response: {response.text}")
        else:
            print(f"❌ Unexpected status code: {response.status_code}")
            print(f"   Response: {response.text}")
            
    except requests.exceptions.Timeout:
        print("❌ Request timed out")
    except requests.exceptions.ConnectionError:
        print("❌ Could not connect to server")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    return None

def test_with_fetched_key():
    """Test using the fetched key locally"""
    
    # Fetch the key from Render
    api_key = fetch_openai_key()
    
    if not api_key:
        print("\n❌ Could not fetch API key from server")
        return 1
    
    print("\n" + "="*60)
    print("Testing local server with fetched key")
    print("="*60)
    
    # Now we can start a local server with the fetched key
    print("\nTo start your local Cedar server with the fetched key:")
    print(f"  export OPENAI_API_KEY='{api_key[:6]}...{api_key[-4:]}'")
    print("  cargo run --bin notebook_server")
    
    print("\nOr use the key directly in your Cedar CLI:")
    print(f"  export CEDAR_SERVER_URL='{CEDAR_SERVER_URL}'")
    print(f"  export APP_SHARED_TOKEN='{APP_TOKEN[:10] if APP_TOKEN else 'your-token'}...'")
    print("  cargo run --bin cedar-cli -- agent --user-prompt 'Hello'")
    
    return 0

def main():
    print("="*60)
    print("Cedar Key Fetch Test from Render")
    print("="*60)
    print()
    
    # Check if we're trying to use the Render server
    print(f"Server: {CEDAR_SERVER_URL}")
    print()
    
    # Test health endpoint (requires token)
    if APP_TOKEN:
        print("Testing health endpoint with token...")
        try:
            response = requests.get(
                f"{CEDAR_SERVER_URL}/health",
                headers={"x-app-token": APP_TOKEN},
                timeout=5
            )
            if response.status_code == 200:
                print("✅ Server is accessible with token")
            else:
                print(f"⚠️  Health check returned: {response.status_code}")
        except Exception as e:
            print(f"❌ Health check failed: {e}")
    else:
        print("⚠️  No APP_SHARED_TOKEN set, skipping health check")
    
    print()
    
    # Try to fetch the key
    return test_with_fetched_key()

if __name__ == "__main__":
    sys.exit(main())
