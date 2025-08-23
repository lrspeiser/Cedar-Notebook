#!/usr/bin/env python3
"""
Comprehensive unit tests for Cedar backend server.
Tests all major endpoints and functionality.
"""

import unittest
import requests
import json
import time
import os
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional

# Server configuration
SERVER_URL = os.getenv("CEDAR_SERVER_URL", "http://localhost:8080")
API_KEY = os.getenv("OPENAI_API_KEY", "")

class TestCedarBackend(unittest.TestCase):
    """Test suite for Cedar backend server"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test fixtures"""
        cls.base_url = SERVER_URL
        cls.api_key = API_KEY
        print(f"\n🌲 Testing Cedar Backend at {cls.base_url}")
        
    def test_01_health_check(self):
        """Test health endpoint"""
        print("\n✅ Testing health check...")
        response = requests.get(f"{self.base_url}/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.text, "ok")
        print("  ✓ Health check passed")
        
    def test_02_cors_headers(self):
        """Test CORS headers are properly set"""
        print("\n✅ Testing CORS headers...")
        response = requests.options(
            f"{self.base_url}/health",
            headers={"Origin": "http://localhost:3000"}
        )
        self.assertIn("access-control-allow-origin", 
                     {k.lower() for k in response.headers.keys()})
        print("  ✓ CORS headers present")
        
    def test_03_submit_query_text(self):
        """Test submitting a text query"""
        print("\n✅ Testing text query submission...")
        
        payload = {
            "prompt": "What is 2 + 2?",
            "api_key": self.api_key
        }
        
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("run_id", data)
        self.assertTrue(data.get("ok", False))
        print(f"  ✓ Query submitted, run_id: {data.get('run_id')}")
        
    def test_04_submit_query_with_file_path(self):
        """Test submitting a query with file information (Tauri path)"""
        print("\n✅ Testing file path submission (Tauri mode)...")
        
        # Create a temporary CSV file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
            f.write("name,age,city\n")
            f.write("Alice,30,NYC\n")
            f.write("Bob,25,LA\n")
            temp_path = f.name
            
        try:
            payload = {
                "file_info": {
                    "name": "test_data.csv",
                    "path": temp_path,
                    "size": os.path.getsize(temp_path),
                    "file_type": "text/csv"
                },
                "api_key": self.api_key
            }
            
            response = requests.post(
                f"{self.base_url}/commands/submit_query",
                json=payload
            )
            
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn("run_id", data)
            print(f"  ✓ File submitted, run_id: {data.get('run_id')}")
            
        finally:
            os.unlink(temp_path)
            
    def test_05_submit_query_with_file_preview(self):
        """Test submitting a query with file preview (web mode)"""
        print("\n✅ Testing file preview submission (web mode)...")
        
        file_preview = """name,age,city
Alice,30,NYC
Bob,25,LA
Charlie,35,Chicago"""
        
        payload = {
            "file_info": {
                "name": "data.csv",
                "size": 1024,
                "file_type": "text/csv",
                "preview": file_preview
            },
            "api_key": self.api_key
        }
        
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("run_id", data)
        print(f"  ✓ Preview submitted, run_id: {data.get('run_id')}")
        
    def test_06_list_runs(self):
        """Test listing recent runs"""
        print("\n✅ Testing run listing...")
        
        response = requests.get(f"{self.base_url}/runs?limit=5")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("runs", data)
        self.assertIsInstance(data["runs"], list)
        print(f"  ✓ Found {len(data['runs'])} runs")
        
    def test_07_sse_endpoint(self):
        """Test SSE endpoint availability"""
        print("\n✅ Testing SSE endpoint...")
        
        # First create a run to get a run_id
        payload = {
            "prompt": "test",
            "api_key": self.api_key
        }
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        
        if response.status_code == 200:
            run_id = response.json().get("run_id")
            
            # Test SSE endpoint exists (won't actually stream)
            sse_url = f"{self.base_url}/runs/{run_id}/events"
            response = requests.get(sse_url, stream=True, timeout=1)
            
            # SSE should return 200 and have event-stream content type
            self.assertEqual(response.status_code, 200)
            content_type = response.headers.get("content-type", "")
            self.assertIn("text/event-stream", content_type)
            response.close()
            print(f"  ✓ SSE endpoint available for run {run_id}")
        
    def test_08_datasets_endpoint(self):
        """Test datasets endpoint"""
        print("\n✅ Testing datasets endpoint...")
        
        response = requests.get(f"{self.base_url}/datasets")
        # It's OK if this returns 404 initially
        if response.status_code == 404:
            print("  ✓ Datasets endpoint returns 404 (normal for fresh install)")
        else:
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIsInstance(data, list)
            print(f"  ✓ Found {len(data)} datasets")
            
    def test_09_julia_execution(self):
        """Test Julia code execution"""
        print("\n✅ Testing Julia execution...")
        
        payload = {
            "code": "println(2 + 2)"
        }
        
        response = requests.post(
            f"{self.base_url}/commands/run_julia",
            json=payload
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("run_id", data)
        self.assertIn("message", data)
        self.assertTrue(data.get("ok", False))
        print(f"  ✓ Julia executed: {data.get('message', '')[:50]}")
        
    def test_10_shell_execution(self):
        """Test shell command execution"""
        print("\n✅ Testing shell execution...")
        
        payload = {
            "cmd": "echo 'Hello from Cedar'"
        }
        
        response = requests.post(
            f"{self.base_url}/commands/run_shell",
            json=payload
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("run_id", data)
        self.assertIn("message", data)
        self.assertTrue(data.get("ok", False))
        print(f"  ✓ Shell executed: {data.get('message', '').strip()}")
        
    def test_11_error_handling_no_api_key(self):
        """Test error handling when no API key provided"""
        print("\n✅ Testing error handling (no API key)...")
        
        payload = {
            "prompt": "test query"
            # Deliberately omitting api_key
        }
        
        # Only test if no environment API key
        if not os.getenv("OPENAI_API_KEY"):
            response = requests.post(
                f"{self.base_url}/commands/submit_query",
                json=payload
            )
            
            self.assertEqual(response.status_code, 500)
            print("  ✓ Properly rejects request without API key")
        else:
            print("  ⚠️  Skipped (environment API key present)")
            
    def test_12_error_handling_invalid_file(self):
        """Test error handling with invalid file path"""
        print("\n✅ Testing error handling (invalid file)...")
        
        payload = {
            "file_info": {
                "name": "nonexistent.csv",
                "path": "/path/that/does/not/exist.csv",
                "size": 0,
                "file_type": "text/csv"
            },
            "api_key": self.api_key
        }
        
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        
        # Should still return 200 but agent will handle the error
        self.assertEqual(response.status_code, 200)
        print("  ✓ Handles invalid file path gracefully")
        
    def test_13_conversation_history(self):
        """Test conversation history support"""
        print("\n✅ Testing conversation history...")
        
        payload = {
            "prompt": "What is the result?",
            "conversation_history": [
                {
                    "query": "Calculate 10 + 5",
                    "response": "The result is 15"
                }
            ],
            "api_key": self.api_key
        }
        
        response = requests.post(
            f"{self.base_url}/commands/submit_query",
            json=payload
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("run_id", data)
        print("  ✓ Conversation history accepted")

class TestCedarIntegration(unittest.TestCase):
    """Integration tests for Cedar backend"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test fixtures"""
        cls.base_url = SERVER_URL
        cls.api_key = API_KEY
        
    def test_end_to_end_csv_processing(self):
        """Test complete CSV processing workflow"""
        print("\n🔄 Testing end-to-end CSV processing...")
        
        # Create test CSV
        csv_content = """product,price,quantity
Widget A,19.99,100
Widget B,29.99,50
Widget C,39.99,75"""
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
            f.write(csv_content)
            temp_path = f.name
            
        try:
            # Submit file for processing
            payload = {
                "file_info": {
                    "name": "products.csv",
                    "path": temp_path,
                    "size": os.path.getsize(temp_path),
                    "file_type": "text/csv",
                    "preview": csv_content
                },
                "api_key": self.api_key
            }
            
            response = requests.post(
                f"{self.base_url}/commands/submit_query",
                json=payload
            )
            
            self.assertEqual(response.status_code, 200)
            data = response.json()
            run_id = data.get("run_id")
            
            print(f"  ✓ File submitted, run_id: {run_id}")
            
            # Wait a bit for processing
            time.sleep(2)
            
            # Check if run artifacts were created
            response = requests.get(f"{self.base_url}/runs/{run_id}/cards")
            if response.status_code == 200:
                cards = response.json().get("cards", [])
                print(f"  ✓ Found {len(cards)} cards for run")
                
        finally:
            os.unlink(temp_path)

def run_tests():
    """Run all tests with nice output"""
    print("\n" + "="*60)
    print("🌲 CEDAR BACKEND TEST SUITE")
    print("="*60)
    
    # Check if server is running
    try:
        response = requests.get(f"{SERVER_URL}/health", timeout=2)
        if response.status_code != 200:
            raise Exception("Server not healthy")
    except Exception as e:
        print(f"\n❌ ERROR: Cedar server not running at {SERVER_URL}")
        print("Please start the server with: ./start_cedar_server.sh")
        return False
    
    # Run tests
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestCedarBackend))
    suite.addTests(loader.loadTestsFromTestCase(TestCedarIntegration))
    
    # Run with verbose output
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Summary
    print("\n" + "="*60)
    if result.wasSuccessful():
        print("✅ ALL TESTS PASSED!")
    else:
        print(f"❌ TESTS FAILED: {len(result.failures)} failures, {len(result.errors)} errors")
    print("="*60 + "\n")
    
    return result.wasSuccessful()

if __name__ == "__main__":
    import sys
    success = run_tests()
    sys.exit(0 if success else 1)
