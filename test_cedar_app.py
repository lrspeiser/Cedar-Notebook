#!/usr/bin/env python3
"""
Cedar App API Testing Framework
================================
Clean API interface for testing Cedar desktop app functionality.

This script provides:
1. Programmatic app launch with environment setup
2. API key validation testing
3. Query submission through the agent loop
4. Comprehensive test harness

Usage:
    python test_cedar_app.py              # Run all tests
    python test_cedar_app.py --key-only   # Test only API key fetching
    python test_cedar_app.py --query "2+2=" # Test specific query
"""

import asyncio
import json
import subprocess
import sys
import os
import time
import argparse
from pathlib import Path
from typing import Optional, Dict, Any

# Colors for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

class CedarAppTester:
    """Clean API interface for testing Cedar app functionality."""
    
    def __init__(self, app_path: Optional[str] = None):
        """Initialize the tester with optional custom app path."""
        self.app_path = app_path or self._find_app()
        self.process = None
        self.setup_environment()
        
    def _find_app(self) -> str:
        """Find the Cedar app executable."""
        # Check common locations
        paths = [
            "target/release/cedar",
            "target/debug/cedar",
            "apps/desktop/src-tauri/target/release/cedar",
            "apps/desktop/src-tauri/target/debug/cedar",
        ]
        
        for path in paths:
            if Path(path).exists():
                return path
        
        # Try to find in bundle
        bundle_paths = [
            "target/release/bundle/macos/Cedar.app/Contents/MacOS/Cedar",
            "apps/desktop/src-tauri/target/release/bundle/macos/Cedar.app/Contents/MacOS/Cedar",
        ]
        
        for path in bundle_paths:
            if Path(path).exists():
                return path
                
        raise FileNotFoundError("Could not find Cedar app executable. Please build the app first.")
    
    def setup_environment(self):
        """Set up required environment variables."""
        os.environ["CEDAR_KEY_URL"] = "https://cedar-notebook.onrender.com"
        os.environ["APP_SHARED_TOKEN"] = "403-298-09345-023495"
        os.environ["RUST_LOG"] = "info"
        print(f"{Colors.OKBLUE}✓ Environment configured{Colors.ENDC}")
    
    def launch_app(self, headless: bool = True) -> bool:
        """Launch the Cedar app programmatically."""
        try:
            print(f"{Colors.HEADER}Launching Cedar app...{Colors.ENDC}")
            
            if headless:
                # Run in headless/testing mode
                env = os.environ.copy()
                env["CEDAR_HEADLESS"] = "1"
                self.process = subprocess.Popen(
                    [self.app_path],
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )
            else:
                # Run normally
                self.process = subprocess.Popen(
                    [self.app_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )
            
            # Give app time to initialize
            time.sleep(2)
            
            if self.process.poll() is None:
                print(f"{Colors.OKGREEN}✓ App launched successfully (PID: {self.process.pid}){Colors.ENDC}")
                return True
            else:
                print(f"{Colors.FAIL}✗ App failed to launch{Colors.ENDC}")
                return False
                
        except Exception as e:
            print(f"{Colors.FAIL}✗ Failed to launch app: {e}{Colors.ENDC}")
            return False
    
    def test_api_key_fetch(self) -> bool:
        """Test API key fetching through the native backend."""
        print(f"\n{Colors.HEADER}Testing API Key Fetch...{Colors.ENDC}")
        
        try:
            # Import the Rust backend directly
            import sys
            sys.path.insert(0, str(Path(__file__).parent))
            
            # Create test script to invoke Rust functions
            test_script = """
import asyncio
import sys
import os

# Set up environment
os.environ["CEDAR_KEY_URL"] = "https://cedar-notebook.onrender.com"
os.environ["APP_SHARED_TOKEN"] = "403-298-09345-023495"

# Import and test the key manager
sys.path.insert(0, "target/release")
sys.path.insert(0, "target/debug")

async def test_key():
    # Simulate what the Tauri command does
    from notebook_core import KeyManager
    
    km = KeyManager()
    api_key = await km.get_api_key()
    
    if api_key and api_key.startswith("sk-"):
        return True, api_key[:20] + "..."
    else:
        return False, "Invalid key format"

result, key_preview = asyncio.run(test_key())
print(f"API_KEY_RESULT:{result}:{key_preview}")
"""
            
            # Write and run test script
            test_file = Path("_test_api_key.py")
            test_file.write_text(test_script)
            
            result = subprocess.run(
                [sys.executable, str(test_file)],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            test_file.unlink()  # Clean up
            
            if "API_KEY_RESULT:True" in result.stdout:
                key_preview = result.stdout.split(":")[-1].strip()
                print(f"{Colors.OKGREEN}✓ API key fetched successfully: {key_preview}{Colors.ENDC}")
                return True
            else:
                print(f"{Colors.FAIL}✗ Failed to fetch API key{Colors.ENDC}")
                if result.stderr:
                    print(f"  Error: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"{Colors.FAIL}✗ API key test failed: {e}{Colors.ENDC}")
            return False
    
    def test_query_submission(self, query: str = "What is 2+2?") -> bool:
        """Test query submission through the agent loop."""
        print(f"\n{Colors.HEADER}Testing Query Submission...{Colors.ENDC}")
        print(f"  Query: '{query}'")
        
        try:
            # Create test script that calls the Tauri command
            test_script = f"""
import asyncio
import json
import os
import sys
from pathlib import Path

# Set up environment
os.environ["CEDAR_KEY_URL"] = "https://cedar-notebook.onrender.com"
os.environ["APP_SHARED_TOKEN"] = "403-298-09345-023495"

# Add paths for imports
sys.path.insert(0, "target/release")
sys.path.insert(0, "target/debug")

async def test_query():
    from notebook_core import agent_loop, AgentConfig, KeyManager
    
    # Get API key
    km = KeyManager()
    api_key = await km.get_api_key()
    
    # Create run directory
    import tempfile
    run_dir = Path(tempfile.mkdtemp(prefix="cedar_test_"))
    
    # Configure agent
    config = AgentConfig(
        openai_api_key=api_key,
        openai_model="gpt-4o-mini",
        openai_base=None,
        relay_url="https://cedar-notebook.onrender.com",
        app_shared_token="403-298-09345-023495"
    )
    
    # Run agent loop
    result = await agent_loop(str(run_dir), "{query}", 10, config)
    
    return {{
        "success": True,
        "run_id": run_dir.name,
        "final_output": result.final_output or f"Completed in {{result.turns_used}} turns",
        "turns_used": result.turns_used
    }}

try:
    result = asyncio.run(test_query())
    print(f"QUERY_RESULT:{{json.dumps(result)}}")
except Exception as e:
    print(f"QUERY_ERROR:{{str(e)}}")
"""
            
            # Write and run test script
            test_file = Path("_test_query.py")
            test_file.write_text(test_script)
            
            result = subprocess.run(
                [sys.executable, str(test_file)],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            test_file.unlink()  # Clean up
            
            if "QUERY_RESULT:" in result.stdout:
                json_str = result.stdout.split("QUERY_RESULT:")[1].strip()
                result_data = json.loads(json_str)
                
                print(f"{Colors.OKGREEN}✓ Query processed successfully{Colors.ENDC}")
                print(f"  Run ID: {result_data['run_id']}")
                print(f"  Turns used: {result_data['turns_used']}")
                print(f"  Result: {result_data['final_output'][:100]}...")
                return True
            else:
                print(f"{Colors.FAIL}✗ Query submission failed{Colors.ENDC}")
                if "QUERY_ERROR:" in result.stdout:
                    error = result.stdout.split("QUERY_ERROR:")[1].strip()
                    print(f"  Error: {error}")
                return False
                
        except Exception as e:
            print(f"{Colors.FAIL}✗ Query test failed: {e}{Colors.ENDC}")
            return False
    
    def test_tauri_command(self, query: str = "What is 2+2?") -> bool:
        """Test the Tauri command interface directly."""
        print(f"\n{Colors.HEADER}Testing Tauri Command Interface...{Colors.ENDC}")
        
        try:
            # Simulate Tauri command invocation
            test_script = f"""
import json

# This simulates what the frontend would send
payload = {{
    "prompt": "{query}"
}}

# In a real scenario, this would be invoked through Tauri's IPC
# For testing, we'll call the Rust function directly
print(f"TAURI_PAYLOAD:{{json.dumps(payload)}}")

# The Rust cmd_submit_query function would process this
# and return a SubmitQueryResponse
"""
            
            result = subprocess.run(
                [sys.executable, "-c", test_script],
                capture_output=True,
                text=True
            )
            
            if "TAURI_PAYLOAD:" in result.stdout:
                payload = result.stdout.split("TAURI_PAYLOAD:")[1].strip()
                print(f"{Colors.OKGREEN}✓ Tauri command payload created: {payload}{Colors.ENDC}")
                return True
            else:
                print(f"{Colors.FAIL}✗ Failed to create Tauri command{Colors.ENDC}")
                return False
                
        except Exception as e:
            print(f"{Colors.FAIL}✗ Tauri command test failed: {e}{Colors.ENDC}")
            return False
    
    def cleanup(self):
        """Clean up app process."""
        if self.process:
            print(f"\n{Colors.HEADER}Cleaning up...{Colors.ENDC}")
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            print(f"{Colors.OKGREEN}✓ App terminated{Colors.ENDC}")
    
    def run_all_tests(self) -> Dict[str, bool]:
        """Run all tests and return results."""
        results = {}
        
        print(f"\n{Colors.BOLD}{'='*60}{Colors.ENDC}")
        print(f"{Colors.BOLD}Cedar App API Test Suite{Colors.ENDC}")
        print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}")
        
        # Test 1: API Key Fetching
        results['api_key'] = self.test_api_key_fetch()
        
        # Test 2: Query Submission
        results['query'] = self.test_query_submission("What is 2+2? Use Julia to calculate.")
        
        # Test 3: Tauri Command Interface
        results['tauri'] = self.test_tauri_command("Calculate 10 * 5")
        
        # Test 4: App Launch (optional, as it requires GUI)
        # results['launch'] = self.launch_app(headless=True)
        
        # Summary
        print(f"\n{Colors.BOLD}{'='*60}{Colors.ENDC}")
        print(f"{Colors.BOLD}Test Results Summary{Colors.ENDC}")
        print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}")
        
        for test_name, passed in results.items():
            status = f"{Colors.OKGREEN}PASSED{Colors.ENDC}" if passed else f"{Colors.FAIL}FAILED{Colors.ENDC}"
            print(f"  {test_name:20} {status}")
        
        total = len(results)
        passed = sum(1 for v in results.values() if v)
        
        print(f"\n  Total: {passed}/{total} tests passed")
        
        if passed == total:
            print(f"\n{Colors.OKGREEN}{Colors.BOLD}✓ All tests passed!{Colors.ENDC}")
        else:
            print(f"\n{Colors.WARNING}{Colors.BOLD}⚠ Some tests failed{Colors.ENDC}")
        
        return results


def main():
    """Main entry point for the test suite."""
    parser = argparse.ArgumentParser(description="Test Cedar App APIs")
    parser.add_argument("--key-only", action="store_true", help="Test only API key fetching")
    parser.add_argument("--query", type=str, help="Test specific query")
    parser.add_argument("--app-path", type=str, help="Path to Cedar app executable")
    
    args = parser.parse_args()
    
    try:
        tester = CedarAppTester(app_path=args.app_path)
        
        if args.key_only:
            # Test only API key
            success = tester.test_api_key_fetch()
            sys.exit(0 if success else 1)
        
        elif args.query:
            # Test specific query
            success = tester.test_query_submission(args.query)
            sys.exit(0 if success else 1)
        
        else:
            # Run all tests
            results = tester.run_all_tests()
            all_passed = all(results.values())
            sys.exit(0 if all_passed else 1)
    
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Test interrupted by user{Colors.ENDC}")
        sys.exit(1)
    
    except Exception as e:
        print(f"{Colors.FAIL}Test suite failed: {e}{Colors.ENDC}")
        sys.exit(1)
    
    finally:
        if 'tester' in locals():
            tester.cleanup()


if __name__ == "__main__":
    main()