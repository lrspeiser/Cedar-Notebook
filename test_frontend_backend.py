#!/usr/bin/env python3
"""
Unit tests that simulate frontend interactions with the Cedar backend.
Tests the complete flow from frontend prompt submission to backend processing.
"""

import json
import time
import requests
import os
import sys
from pathlib import Path

# Backend URL
API_URL = "http://localhost:8080"

# Color codes for output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'


def print_test_header(test_name):
    """Print a formatted test header"""
    print(f"\n{BLUE}{'='*60}{RESET}")
    print(f"{BLUE}TEST: {test_name}{RESET}")
    print(f"{BLUE}{'='*60}{RESET}")


def print_success(message):
    """Print success message in green"""
    print(f"{GREEN}✓ {message}{RESET}")


def print_error(message):
    """Print error message in red"""
    print(f"{RED}✗ {message}{RESET}")


def print_info(message):
    """Print info message in yellow"""
    print(f"{YELLOW}ℹ {message}{RESET}")


class TestCedarBackend:
    """Test suite for Cedar backend API endpoints"""
    
    def __init__(self):
        self.api_url = API_URL
        self.test_results = []
        
    def check_health(self):
        """Test 1: Check if backend server is running"""
        print_test_header("Server Health Check")
        
        try:
            response = requests.get(f"{self.api_url}/health", timeout=5)
            if response.status_code == 200:
                print_success("Backend server is running")
                return True
            else:
                print_error(f"Server returned status code: {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print_error("Cannot connect to backend server")
            print_info(f"Make sure the server is running at {self.api_url}")
            print_info("Run: ./start_cedar_server.sh")
            return False
        except Exception as e:
            print_error(f"Unexpected error: {e}")
            return False
    
    def test_simple_math_query(self):
        """Test 2: Submit a simple math query (2+2)"""
        print_test_header("Simple Math Query (2+2)")
        
        # This simulates what the frontend does when user types "What is 2+2?"
        request_body = {
            "prompt": "What is 2+2?"
        }
        
        try:
            print_info("Submitting query: 'What is 2+2?'")
            
            response = requests.post(
                f"{self.api_url}/commands/submit_query",
                json=request_body,
                timeout=30
            )
            
            if response.status_code != 200:
                print_error(f"Server returned status code: {response.status_code}")
                print_error(f"Response: {response.text}")
                return False
            
            result = response.json()
            
            # Check required fields
            if "run_id" not in result:
                print_error("Response missing 'run_id' field")
                return False
            
            if "ok" not in result or not result["ok"]:
                print_error("Response indicates failure")
                return False
                
            print_success(f"Got run_id: {result['run_id']}")
            
            # Check if we got a response
            if "response" in result and result["response"]:
                print_success(f"Response: {result['response']}")
                
                # Verify the answer contains "4"
                if "4" in str(result["response"]):
                    print_success("Answer correctly contains '4'")
                else:
                    print_error("Answer doesn't contain expected result '4'")
                    return False
            
            # Check if Julia code was generated
            if "julia_code" in result and result["julia_code"]:
                print_info(f"Generated Julia code: {result['julia_code']}")
            
            # Check execution output
            if "execution_output" in result and result["execution_output"]:
                print_info(f"Execution output: {result['execution_output']}")
                
            return True
            
        except requests.exceptions.Timeout:
            print_error("Request timed out after 30 seconds")
            return False
        except Exception as e:
            print_error(f"Unexpected error: {e}")
            return False
    
    def test_csv_file_processing(self):
        """Test 3: Simulate CSV file upload and processing"""
        print_test_header("CSV File Processing")
        
        # Create a test CSV file if it doesn't exist
        csv_file_path = Path.home() / "Downloads" / "test_data_backend.csv"
        
        if not csv_file_path.exists():
            print_info("Creating test CSV file...")
            csv_content = """product,quantity,price,date
Laptop,5,1299.99,2024-01-15
Mouse,25,29.99,2024-01-16
Keyboard,12,89.99,2024-01-17
Monitor,8,399.99,2024-01-18
Tablet,3,599.99,2024-01-19
"""
            csv_file_path.write_text(csv_content)
            print_success(f"Created test file: {csv_file_path}")
        else:
            print_info(f"Using existing test file: {csv_file_path}")
        
        # This simulates what the frontend does when user selects a file
        request_body = {
            "prompt": f'Process the file named "{csv_file_path.name}" that I just selected'
        }
        
        try:
            print_info(f"Submitting file processing request for: {csv_file_path.name}")
            
            response = requests.post(
                f"{self.api_url}/commands/submit_query",
                json=request_body,
                timeout=60  # Give more time for file processing
            )
            
            if response.status_code != 200:
                print_error(f"Server returned status code: {response.status_code}")
                print_error(f"Response: {response.text}")
                return False
            
            result = response.json()
            
            # Check basic response structure
            if "run_id" not in result:
                print_error("Response missing 'run_id' field")
                return False
            
            if "ok" not in result or not result["ok"]:
                print_error("Response indicates failure")
                return False
            
            print_success(f"Got run_id: {result['run_id']}")
            
            # Check if response mentions finding or processing the file
            if "response" in result and result["response"]:
                response_text = result["response"].lower()
                print_info(f"Response preview: {result['response'][:200]}...")
                
                # Check for indicators of successful processing
                success_indicators = ["found", "loaded", "processed", "csv", "rows", "columns"]
                if any(indicator in response_text for indicator in success_indicators):
                    print_success("Response indicates file was processed")
                else:
                    print_info("Response doesn't clearly indicate file processing")
            
            # Check if Julia code was generated
            if "julia_code" in result and result["julia_code"]:
                print_success("Julia code was generated for file processing")
                print_info(f"Julia code preview: {result['julia_code'][:100]}...")
            
            # Check execution output
            if "execution_output" in result and result["execution_output"]:
                print_success("File processing generated execution output")
                print_info(f"Output preview: {result['execution_output'][:200]}...")
            
            return True
            
        except requests.exceptions.Timeout:
            print_error("Request timed out after 60 seconds")
            return False
        except Exception as e:
            print_error(f"Unexpected error: {e}")
            return False
    
    def test_dataset_listing(self):
        """Test 4: List available datasets"""
        print_test_header("Dataset Listing")
        
        try:
            print_info("Fetching dataset list...")
            
            response = requests.get(f"{self.api_url}/datasets", timeout=10)
            
            if response.status_code != 200:
                print_error(f"Server returned status code: {response.status_code}")
                print_error(f"Response: {response.text}")
                return False
            
            result = response.json()
            
            # Check if response has datasets field
            if "datasets" not in result:
                print_error("Response missing 'datasets' field")
                return False
            
            datasets = result["datasets"]
            print_success(f"Found {len(datasets)} dataset(s)")
            
            # List datasets if any exist
            if datasets:
                for ds in datasets[:3]:  # Show first 3 datasets
                    print_info(f"  - {ds.get('title', 'Untitled')} ({ds.get('file_name', 'Unknown')})")
                    print_info(f"    Rows: {ds.get('row_count', 0)}, Columns: {ds.get('column_count', 0)}")
            else:
                print_info("No datasets currently loaded")
            
            return True
            
        except Exception as e:
            print_error(f"Unexpected error: {e}")
            return False
    
    def test_complex_data_query(self):
        """Test 5: Submit a complex data analysis query"""
        print_test_header("Complex Data Analysis Query")
        
        request_body = {
            "prompt": "Create a Julia script that generates a 10x10 matrix of random numbers between 1 and 100, then calculate the mean, median, and standard deviation"
        }
        
        try:
            print_info("Submitting complex data analysis query...")
            
            response = requests.post(
                f"{self.api_url}/commands/submit_query",
                json=request_body,
                timeout=45
            )
            
            if response.status_code != 200:
                print_error(f"Server returned status code: {response.status_code}")
                return False
            
            result = response.json()
            
            if "ok" not in result or not result["ok"]:
                print_error("Response indicates failure")
                return False
            
            print_success(f"Got run_id: {result['run_id']}")
            
            # Check if Julia code was generated
            if "julia_code" in result and result["julia_code"]:
                julia_code = result["julia_code"]
                print_success("Julia code generated successfully")
                
                # Check for expected Julia constructs
                expected_keywords = ["rand", "mean", "median", "std"]
                found_keywords = [kw for kw in expected_keywords if kw in julia_code.lower()]
                
                if found_keywords:
                    print_success(f"Julia code contains expected functions: {', '.join(found_keywords)}")
                else:
                    print_info("Julia code doesn't contain expected statistical functions")
            
            # Check execution output
            if "execution_output" in result and result["execution_output"]:
                print_success("Code was executed successfully")
                output = result["execution_output"]
                
                # Check if output contains numerical results
                if any(char.isdigit() for char in output):
                    print_success("Output contains numerical results")
                    print_info(f"Output preview: {output[:200]}...")
            
            return True
            
        except Exception as e:
            print_error(f"Unexpected error: {e}")
            return False
    
    def run_all_tests(self):
        """Run all tests and report results"""
        print(f"\n{BLUE}{'='*60}{RESET}")
        print(f"{BLUE}CEDAR BACKEND TEST SUITE{RESET}")
        print(f"{BLUE}Testing frontend-backend integration{RESET}")
        print(f"{BLUE}{'='*60}{RESET}")
        
        # Check server health first
        if not self.check_health():
            print(f"\n{RED}Cannot proceed with tests - server not available{RESET}")
            return False
        
        # Run all tests
        tests = [
            ("Simple Math Query", self.test_simple_math_query),
            ("CSV File Processing", self.test_csv_file_processing),
            ("Dataset Listing", self.test_dataset_listing),
            ("Complex Data Query", self.test_complex_data_query),
        ]
        
        results = []
        for test_name, test_func in tests:
            try:
                result = test_func()
                results.append((test_name, result))
            except Exception as e:
                print_error(f"Test '{test_name}' crashed: {e}")
                results.append((test_name, False))
        
        # Print summary
        print(f"\n{BLUE}{'='*60}{RESET}")
        print(f"{BLUE}TEST SUMMARY{RESET}")
        print(f"{BLUE}{'='*60}{RESET}")
        
        passed = sum(1 for _, result in results if result)
        total = len(results)
        
        for test_name, result in results:
            status = f"{GREEN}PASSED{RESET}" if result else f"{RED}FAILED{RESET}"
            print(f"  {test_name}: {status}")
        
        print(f"\n{BLUE}Results: {passed}/{total} tests passed{RESET}")
        
        if passed == total:
            print(f"{GREEN}✓ All tests passed!{RESET}")
            return True
        else:
            print(f"{RED}✗ Some tests failed{RESET}")
            return False


def main():
    """Main test runner"""
    tester = TestCedarBackend()
    
    # Check if we should run a specific test
    if len(sys.argv) > 1:
        test_name = sys.argv[1]
        if test_name == "math":
            tester.check_health() and tester.test_simple_math_query()
        elif test_name == "csv":
            tester.check_health() and tester.test_csv_file_processing()
        elif test_name == "datasets":
            tester.check_health() and tester.test_dataset_listing()
        elif test_name == "complex":
            tester.check_health() and tester.test_complex_data_query()
        else:
            print(f"Unknown test: {test_name}")
            print("Available tests: math, csv, datasets, complex")
    else:
        # Run all tests
        success = tester.run_all_tests()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
