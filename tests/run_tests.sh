#!/bin/bash
# Run Cedar backend tests

echo "🌲 Cedar Backend Test Runner"
echo "============================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if server is running
echo -e "\n${YELLOW}Checking server status...${NC}"
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server is running${NC}"
else
    echo -e "${RED}✗ Server is not running${NC}"
    echo "Starting server..."
    cd ~/Projects/cedarcli
    export OPENAI_API_KEY="${OPENAI_API_KEY}"
    nohup cargo run --release --bin notebook_server > server_output.log 2>&1 &
    echo "Waiting for server to start..."
    sleep 5
    
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Server started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start server${NC}"
        echo "Please check server_output.log for errors"
        exit 1
    fi
fi

# Run tests
echo -e "\n${YELLOW}Running test suite...${NC}"
python3 ~/Projects/cedarcli/test_frontend_backend.py

# Check exit code
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests completed successfully!${NC}"
else
    echo -e "\n${RED}✗ Some tests failed${NC}"
    exit 1
fi
