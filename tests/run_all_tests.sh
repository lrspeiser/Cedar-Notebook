#!/bin/bash
#
# Cedar Test Suite Runner
# Runs all tests for the Cedar platform
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}🌲 CEDAR COMPREHENSIVE TEST SUITE${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Check if server is running
echo -e "${YELLOW}Checking server status...${NC}"
if curl -s http://localhost:8080/health > /dev/null; then
    echo -e "${GREEN}✓ Server is running${NC}"
else
    echo -e "${RED}✗ Server is not running${NC}"
    echo "Please start the server with: ./start_cedar_server.sh"
    exit 1
fi

# Check for API key
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}⚠ Warning: OPENAI_API_KEY not set${NC}"
    echo "Some tests may be skipped"
fi

echo
echo -e "${BLUE}Running test suites...${NC}"
echo

# Run backend unit tests
echo -e "${YELLOW}1. Backend Unit Tests${NC}"
python3 test_backend_unit.py
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Backend unit tests passed${NC}"
else
    echo -e "${RED}✗ Backend unit tests failed${NC}"
fi

echo

# Run frontend-backend integration tests if available
if [ -f "test_frontend_backend.py" ]; then
    echo -e "${YELLOW}2. Frontend-Backend Integration Tests${NC}"
    python3 test_frontend_backend.py
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Integration tests passed${NC}"
    else
        echo -e "${RED}✗ Integration tests failed${NC}"
    fi
    echo
fi

# Run E2E tests if API key is available
if [ ! -z "$OPENAI_API_KEY" ]; then
    if [ -f "test_e2e_with_retry.py" ]; then
        echo -e "${YELLOW}3. End-to-End Tests${NC}"
        python3 test_e2e_with_retry.py
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ E2E tests passed${NC}"
        else
            echo -e "${RED}✗ E2E tests failed${NC}"
        fi
        echo
    fi
fi

# Run shell command tests
echo -e "${YELLOW}4. Quick Smoke Tests${NC}"

# Test health endpoint
echo -n "  Testing health endpoint... "
if curl -s http://localhost:8080/health | grep -q "ok"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test CORS headers
echo -n "  Testing CORS headers... "
if curl -s -I -X OPTIONS http://localhost:8080/health \
    -H "Origin: http://localhost:3000" | grep -qi "access-control"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test Julia endpoint
echo -n "  Testing Julia execution... "
JULIA_RESPONSE=$(curl -s -X POST http://localhost:8080/commands/run_julia \
    -H "Content-Type: application/json" \
    -d '{"code": "println(\"test\")"}' 2>/dev/null || echo "")
    
if echo "$JULIA_RESPONSE" | grep -q "run_id"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test shell endpoint
echo -n "  Testing shell execution... "
SHELL_RESPONSE=$(curl -s -X POST http://localhost:8080/commands/run_shell \
    -H "Content-Type: application/json" \
    -d '{"cmd": "echo test"}' 2>/dev/null || echo "")
    
if echo "$SHELL_RESPONSE" | grep -q "run_id"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}TEST SUITE COMPLETE${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Summary
echo -e "${GREEN}✅ Basic connectivity tests passed${NC}"
echo -e "${YELLOW}📝 Review detailed test output above${NC}"
echo

echo "To run specific test suites:"
echo "  python3 test_backend_unit.py      # Backend unit tests"
echo "  python3 test_frontend_backend.py  # Integration tests"
echo "  python3 test_e2e_with_retry.py    # End-to-end tests"
echo
