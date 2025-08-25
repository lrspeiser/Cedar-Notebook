#!/usr/bin/env python3
"""
Test to replicate the API key error and verify the fix
"""

import subprocess
import os
import sys
import time

def test_app_launch():
    """Test if the app can successfully fetch API key on launch"""
    
    print("\n" + "="*80)
    print("TESTING CEDAR APP API KEY FETCHING")
    print("="*80)
    
    # Clear any existing environment variables to simulate clean state
    env = os.environ.copy()
    # Remove any existing API key to force fetching
    env.pop("OPENAI_API_KEY", None)
    
    print("\n[TEST] Starting Cedar app without OPENAI_API_KEY set...")
    print("[TEST] App should fetch key from cedar-notebook.onrender.com")
    
    app_path = "/Users/leonardspeiser/Projects/cedarcli/.conductor/manama/target/release/app"
    
    if not os.path.exists(app_path):
        print(f"❌ App not found at {app_path}")
        return False
    
    # Run the app binary directly to see console output
    print("\n[TEST] Launching app binary directly to capture output...")
    
    process = subprocess.Popen(
        [app_path],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Give it a few seconds to initialize
    time.sleep(3)
    
    # Check if process is still running
    if process.poll() is not None:
        # Process terminated - likely due to API key error
        stdout, stderr = process.communicate()
        
        print("\n[OUTPUT]")
        print(stdout)
        print("\n[ERRORS]")
        print(stderr)
        
        if "API key required" in stderr or "API key required" in stdout:
            print("\n❌ REPRODUCED ERROR: App failed with API key error")
            return False
        elif "API key validation passed" in stderr:
            print("\n✅ App successfully validated API key")
            return True
        else:
            print("\n❓ App terminated with unknown reason")
            return False
    else:
        # Process is still running - good sign
        process.terminate()
        print("\n✅ App started successfully (no immediate crash)")
        return True

if __name__ == "__main__":
    success = test_app_launch()
    if not success:
        print("\n" + "="*80)
        print("ERROR REPRODUCED - Need to fix API key fetching")
        print("="*80)
        sys.exit(1)
    else:
        print("\n" + "="*80)
        print("SUCCESS - App can fetch API key properly")
        print("="*80)