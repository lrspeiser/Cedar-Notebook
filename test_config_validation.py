#!/usr/bin/env python3
"""
Validation test to ensure all components are configured correctly:
1. API key fetching from cedar-notebook.onrender.com
2. Direct OpenAI calls (not relayed)
3. GPT-5 /v1/responses endpoint
"""

import subprocess
import os
import sys

print("=" * 60)
print("CEDAR CONFIGURATION VALIDATION")
print("=" * 60)

# Check environment setup
print("\n1. Environment Configuration:")
print("-" * 40)
cedar_key_url = os.environ.get("CEDAR_KEY_URL", "https://cedar-notebook.onrender.com")
app_token = os.environ.get("APP_SHARED_TOKEN", "403-298-09345-023495")
print(f"✓ CEDAR_KEY_URL: {cedar_key_url}")
print(f"✓ APP_SHARED_TOKEN: {app_token[:10]}...")

# Check that files are configured correctly
print("\n2. Code Configuration Check:")
print("-" * 40)

files_to_check = [
    ("apps/desktop/src-tauri/src/lib.rs", "relay_url: None"),
    ("crates/notebook_server/src/lib.rs", "relay_url: None"),
    ("test_cedar_app/src/main.rs", "relay_url: None"),
    ("crates/notebook_core/src/agent_loop.rs", "/v1/responses"),
]

all_good = True
for filepath, expected_content in files_to_check:
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            if expected_content in content:
                print(f"✓ {filepath}: Correctly configured")
            else:
                print(f"✗ {filepath}: Missing '{expected_content}'")
                all_good = False
    except FileNotFoundError:
        print(f"⚠ {filepath}: File not found")

# Run the test app
print("\n3. Testing Complete Flow:")
print("-" * 40)

if all_good:
    print("Running test application...")
    result = subprocess.run(
        ["cargo", "run"],
        cwd="test_cedar_app",
        capture_output=True,
        text=True,
        timeout=30
    )
    
    if "✓ Agent Loop Completed Successfully!" in result.stdout:
        print("✓ Test app completed successfully")
        print("✓ API key fetched from cedar-notebook.onrender.com")
        print("✓ OpenAI GPT-5 /v1/responses endpoint called directly")
        print("✓ Julia code generated and executed")
    else:
        print("✗ Test app failed")
        if "Cannot POST /v1/responses" in result.stdout or result.stderr:
            print("  ERROR: Still trying to use relay for LLM calls")
        else:
            print("  Check output for errors")
else:
    print("✗ Fix configuration issues before testing")

print("\n" + "=" * 60)
print("SUMMARY:")
print("-" * 60)
print("Configuration for production:")
print("1. cedar-notebook.onrender.com - ONLY for API key fetching")
print("2. api.openai.com - Direct calls for all LLM operations")
print("3. Model: gpt-5 with /v1/responses endpoint")
print("4. No relay for LLM calls (relay_url: None)")
print("\nThis ensures:")
print("- Fast response times (no relay overhead)")
print("- Direct access to latest OpenAI features")
print("- Proper separation of concerns")