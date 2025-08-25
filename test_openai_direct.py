#!/usr/bin/env python3
"""
Test calling OpenAI directly with the GPT-5 /v1/responses endpoint
to see the actual request and response
"""

import requests
import json
import os
import subprocess
import sys

# First, get the API key from the cedar server
def get_api_key():
    """Fetch the API key from cedar-notebook.onrender.com"""
    url = "https://cedar-notebook.onrender.com/v1/key"
    headers = {
        "x-app-token": "403-298-09345-023495"
    }
    
    print("Fetching API key from cedar-notebook.onrender.com...")
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        key = data.get("openai_api_key")
        if key:
            print(f"✓ Got API key: {key[:7]}...{key[-4:]}")
            return key
    
    # Try alternate endpoint
    url = "https://cedar-notebook.onrender.com/config/openai_key"
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        key = data.get("openai_api_key")
        if key:
            print(f"✓ Got API key: {key[:7]}...{key[-4:]}")
            return key
    
    print(f"Failed to get API key: {response.status_code}")
    print(response.text)
    return None

# Get the API key
api_key = get_api_key()
if not api_key:
    print("Could not fetch API key")
    sys.exit(1)

print("\n" + "=" * 60)
print("Testing OpenAI GPT-5 /v1/responses endpoint directly")
print("=" * 60)

# Test the GPT-5 responses endpoint
url = "https://api.openai.com/v1/responses"
headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}

# The request body as configured in the Rust code
body = {
    "model": "gpt-5",
    "input": """Return only valid JSON for the given schema. No prose.

You are a computational assistant that runs Julia code to answer questions. When given ANY math or data question, you MUST use Julia to compute the answer. ALWAYS use run_julia for ANY calculations or data questions - never skip directly to final answer. If you want to show sample data or results in user_message, run the actual code first then explain it.

Available tools:
- run_julia: Execute Julia code
- shell: Execute shell commands
- more_from_user: Ask user for clarification
- final: Provide final answer

Output JSON matching this schema:
{
  "action": "run_julia" | "shell" | "more_from_user" | "final",
  "args": {...}
}

--- Transcript ---
[user] Calculate 2 + 2 using Julia

--- Tool context ---
null
--- End ---
""",
    "text": {
        "format": {
            "type": "json_object"
        }
    }
}

print(f"\nRequest URL: {url}")
print(f"\nRequest Headers:")
print(f"  Authorization: Bearer {api_key[:7]}...{api_key[-4:]}")
print(f"  Content-Type: application/json")
print(f"\nRequest Body:")
print(json.dumps(body, indent=2))

print("\n" + "-" * 60)
print("Sending request to OpenAI...")
print("-" * 60)

try:
    response = requests.post(url, headers=headers, json=body, timeout=30)
    
    print(f"\nResponse Status: {response.status_code}")
    print(f"Response Headers:")
    for key, value in response.headers.items():
        if key.lower() in ['content-type', 'date', 'x-request-id', 'openai-model', 'openai-version']:
            print(f"  {key}: {value}")
    
    print(f"\nResponse Body:")
    if response.status_code == 200:
        # Pretty print JSON response
        data = response.json()
        print(json.dumps(data, indent=2))
    else:
        # Show error response
        print(response.text[:1000])
        if len(response.text) > 1000:
            print("... (truncated)")
    
except Exception as e:
    print(f"Error: {e}")

print("\n" + "=" * 60)
print("Analysis:")
print("-" * 60)

if response.status_code == 200:
    print("✓ GPT-5 /v1/responses endpoint works!")
    print("✓ OpenAI accepts the request format")
    print("✓ The model responded with valid output")
elif response.status_code == 404:
    print("✗ Endpoint not found - GPT-5 /v1/responses doesn't exist on OpenAI")
    print("  This suggests the endpoint is fictional or not yet released")
elif response.status_code == 401:
    print("✗ Authentication failed - API key might be invalid")
elif response.status_code == 400:
    print("✗ Bad request - The request format might be incorrect")
else:
    print(f"✗ Unexpected status code: {response.status_code}")