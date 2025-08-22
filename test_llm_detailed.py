#!/usr/bin/env python3
"""
Detailed LLM Interaction Test
Shows exactly what the LLM receives and returns
"""

import requests
import json
import time
from datetime import datetime

API_BASE = "http://localhost:8080"

def colored(text, color):
    """Add color to terminal output"""
    colors = {
        'green': '\033[92m',
        'red': '\033[91m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'cyan': '\033[96m',
        'magenta': '\033[95m',
        'reset': '\033[0m'
    }
    return f"{colors.get(color, '')}{text}{colors['reset']}"

def print_section(title, color='blue'):
    """Print a section header"""
    print(f"\n{colored('=' * 60, color)}")
    print(colored(title, color))
    print(colored('=' * 60, color))

def test_query(prompt, description):
    """Test a specific query and show detailed results"""
    print_section(f"Testing: {description}", 'cyan')
    print(f"\n📝 Prompt: {colored(prompt, 'yellow')}")
    
    payload = {
        "prompt": prompt,
        "datasets": [],
        "file_context": None
    }
    
    print(f"\n📤 Sending to backend...")
    print(f"   Endpoint: {API_BASE}/commands/submit_query")
    print(f"   Payload: {json.dumps(payload, indent=2)}")
    
    start_time = time.time()
    
    try:
        response = requests.post(
            f"{API_BASE}/commands/submit_query",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        elapsed = time.time() - start_time
        print(f"\n⏱️  Response time: {elapsed:.2f} seconds")
        
        if response.status_code == 200:
            result = response.json()
            
            print(f"\n✅ {colored('SUCCESS', 'green')} - Status: {response.status_code}")
            
            # Show each field of the response
            print(f"\n📥 {colored('Response Details:', 'magenta')}")
            
            if result.get('run_id'):
                print(f"\n🔑 Run ID: {result['run_id']}")
            
            if result.get('response'):
                print(f"\n💬 {colored('Final Answer:', 'green')}")
                print(f"   {result['response']}")
            
            if result.get('julia_code'):
                print(f"\n📝 {colored('Generated Julia Code:', 'cyan')}")
                print("   " + "\n   ".join(result['julia_code'].split('\n')))
            
            if result.get('execution_output'):
                print(f"\n🖥️  {colored('Execution Output:', 'yellow')}")
                print("   " + "\n   ".join(result['execution_output'].split('\n')))
            
            if result.get('decision'):
                print(f"\n🤔 {colored('LLM Decision:', 'magenta')}")
                print(f"   {result['decision']}")
            
            # Show raw JSON for debugging
            print(f"\n📄 {colored('Raw JSON Response:', 'blue')}")
            print(json.dumps(result, indent=2))
            
            return True
            
        else:
            print(f"\n❌ {colored('FAILED', 'red')} - Status: {response.status_code}")
            print(f"Error: {response.text[:500]}")
            return False
            
    except requests.exceptions.Timeout:
        print(f"\n❌ {colored('TIMEOUT', 'red')} - Request took longer than 60 seconds")
        return False
    except Exception as e:
        print(f"\n❌ {colored('ERROR', 'red')}: {str(e)}")
        return False

def main():
    print_section("DETAILED LLM INTERACTION TEST", 'magenta')
    print(f"\nBackend: {API_BASE}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Check server is running
    try:
        health = requests.get(f"{API_BASE}/health", timeout=2)
        if health.status_code == 200:
            print(f"\n✅ Server is {colored('ONLINE', 'green')}")
        else:
            print(f"\n❌ Server returned status {health.status_code}")
            return
    except:
        print(f"\n❌ {colored('Cannot connect to server!', 'red')}")
        print("Please start the server with: ./start_cedar_server.sh")
        return
    
    # Test queries to show LLM behavior
    test_cases = [
        {
            "prompt": "What is 2+2? Just give me the number.",
            "description": "Simple Math Question"
        },
        {
            "prompt": "Calculate the sum of 15 and 27, then multiply by 3",
            "description": "Multi-step Calculation"
        },
        {
            "prompt": "Create a Julia function to calculate fibonacci numbers",
            "description": "Code Generation Request"
        },
        {
            "prompt": "What's the weather today?",
            "description": "Non-computational Question"
        },
        {
            "prompt": "Generate 5 random numbers between 1 and 100 using Julia",
            "description": "Julia Code Execution Request"
        }
    ]
    
    results = []
    
    for i, test in enumerate(test_cases, 1):
        print(f"\n{colored(f'[TEST {i}/{len(test_cases)}]', 'yellow')}")
        success = test_query(test['prompt'], test['description'])
        results.append((test['description'], success))
        
        # Add delay between tests to avoid overwhelming the server
        if i < len(test_cases):
            print(f"\n⏳ Waiting 2 seconds before next test...")
            time.sleep(2)
    
    # Summary
    print_section("TEST SUMMARY", 'blue')
    
    passed = sum(1 for _, success in results if success)
    failed = len(results) - passed
    
    print(f"\n📊 Results:")
    for desc, success in results:
        status = colored("✅ PASS", "green") if success else colored("❌ FAIL", "red")
        print(f"   {status} - {desc}")
    
    print(f"\n📈 Total: {passed} passed, {failed} failed out of {len(results)} tests")
    
    if passed == len(results):
        print(f"\n🎉 {colored('All tests passed! The LLM integration is working correctly.', 'green')}")
    else:
        print(f"\n⚠️  {colored(f'{failed} test(s) failed. Check the details above.', 'yellow')}")

if __name__ == "__main__":
    main()
