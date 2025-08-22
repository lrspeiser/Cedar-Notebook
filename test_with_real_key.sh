#!/bin/bash

# Cedar Server Test with Real OpenAI Key
# This script helps test the file upload functionality with a real OpenAI API key

echo "============================================================"
echo "Cedar Server Test with Real OpenAI Key"
echo "============================================================"
echo

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ Error: OPENAI_API_KEY environment variable is not set"
    echo
    echo "Please set your OpenAI API key first:"
    echo "  export OPENAI_API_KEY='sk-your-actual-key-here'"
    echo
    echo "You can get your API key from: https://platform.openai.com/api-keys"
    exit 1
fi

# Validate key format
if [[ ! "$OPENAI_API_KEY" =~ ^sk-[a-zA-Z0-9]{48,}$ ]]; then
    echo "⚠️  Warning: API key doesn't match expected format (sk-...)"
    echo "   Make sure you're using a valid OpenAI API key"
fi

echo "✅ OpenAI API key is set (length: ${#OPENAI_API_KEY})"
echo

# Kill any existing server
echo "Stopping any existing server..."
pkill -f notebook_server 2>/dev/null
sleep 1

# Start the server with the API key
echo "Starting Cedar server with OpenAI API key..."
OPENAI_API_KEY="$OPENAI_API_KEY" cargo run --bin notebook_server > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
echo "Waiting for server to start..."
for i in {1..10}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ Server is running!"
        break
    fi
    echo -n "."
    sleep 1
done
echo

# Test the OpenAI key endpoint
echo "Testing OpenAI key endpoint..."
KEY_RESPONSE=$(curl -s http://localhost:8080/config/openai_key)
if echo "$KEY_RESPONSE" | grep -q "openai_api_key"; then
    echo "✅ OpenAI key endpoint is working"
    echo "   Response: $(echo $KEY_RESPONSE | jq -r '.source')"
else
    echo "❌ OpenAI key endpoint failed"
    echo "   Response: $KEY_RESPONSE"
fi
echo

# Create test CSV file
echo "Creating test CSV file..."
cat > test_data.csv << EOF
name,age,city,occupation
Alice Johnson,30,New York,Software Engineer
Bob Smith,25,Los Angeles,Data Scientist
Charlie Davis,35,Chicago,Product Manager
Diana Wilson,28,San Francisco,UX Designer
Edward Brown,42,Seattle,DevOps Engineer
EOF
echo "✅ Test file created: test_data.csv"
echo

# Test file upload
echo "Testing file upload with LLM enhancement..."
echo "This will use OpenAI to analyze the data and generate metadata..."
echo

python3 << 'PYTHON_SCRIPT'
import requests
import json
import sys

url = "http://localhost:8080/datasets/upload"
test_file = "test_data.csv"

print(f"Uploading {test_file} to {url}")
print()

with open(test_file, 'rb') as f:
    files = {'file': (test_file, f, 'text/csv')}
    
    try:
        response = requests.post(url, files=files, timeout=30)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print("✅ Upload successful!")
            print("\nResponse data:")
            data = response.json()
            print(json.dumps(data, indent=2))
            
            if 'datasets' in data and len(data['datasets']) > 0:
                dataset = data['datasets'][0]
                print("\n📊 Dataset Summary:")
                print(f"   ID: {dataset.get('id', 'N/A')}")
                print(f"   Title: {dataset.get('title', 'N/A')}")
                print(f"   Description: {dataset.get('description', 'N/A')}")
                print(f"   Columns: {dataset.get('column_count', 'N/A')}")
        else:
            print(f"❌ Upload failed with status {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.Timeout:
        print("❌ Request timed out (LLM call may be taking too long)")
    except Exception as e:
        print(f"❌ Error: {e}")
PYTHON_SCRIPT

echo
echo "============================================================"
echo "Test complete!"
echo
echo "Server is still running (PID: $SERVER_PID)"
echo "To stop the server: kill $SERVER_PID"
echo "To view server logs: tail -f server.log"
echo "============================================================"
