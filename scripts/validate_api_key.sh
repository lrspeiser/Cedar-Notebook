#!/bin/bash

# Cedar API Key Validation Script
# This script validates that the API key fetching mechanism works before building the DMG
# It must succeed for the build to proceed

set -e

echo "================================================"
echo "Cedar API Key Validation"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to test API key fetching from onrender server
test_onrender_fetch() {
    local KEY_URL="${CEDAR_KEY_URL:-https://cedar-notebook.onrender.com/v1/key}"
    local TOKEN="${APP_SHARED_TOKEN:-403-298-09345-023495}"
    
    echo "Testing key fetch from: $KEY_URL"
    echo "Using APP_SHARED_TOKEN: ${TOKEN:0:10}..."
    
    # Try to fetch the key
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "x-app-token: $TOKEN" \
        "$KEY_URL" 2>/dev/null || echo "CURL_ERROR")
    
    # Extract HTTP status code
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "HTTP_STATUS:")
    
    if [[ "$RESPONSE" == *"CURL_ERROR"* ]]; then
        echo -e "${RED}❌ Failed to connect to key server${NC}"
        return 1
    fi
    
    if [[ "$HTTP_STATUS" -ne 200 ]]; then
        echo -e "${RED}❌ Server returned HTTP $HTTP_STATUS${NC}"
        echo "Response body: $BODY"
        return 1
    fi
    
    # Check if response contains a valid key
    if echo "$BODY" | grep -q '"openai_api_key".*"sk-'; then
        echo -e "${GREEN}✅ Successfully fetched API key from onrender server${NC}"
        
        # Extract and validate key format
        KEY=$(echo "$BODY" | grep -o '"openai_api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"openai_api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        
        if [[ ${#KEY} -ge 40 ]] && [[ "$KEY" == sk-* ]]; then
            echo -e "${GREEN}✅ Key format is valid (${KEY:0:6}...${KEY: -4})${NC}"
            return 0
        else
            echo -e "${RED}❌ Invalid key format${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Response does not contain valid API key${NC}"
        echo "Response: $BODY"
        return 1
    fi
}

# Function to test local keychain storage
test_keychain_storage() {
    echo "Testing keychain storage capability..."
    
    # Try to write a test entry to keychain
    if command -v security >/dev/null 2>&1; then
        # Write test value
        security add-generic-password -a "cedar-test" -s "cedar-test-key" -w "test-value" >/dev/null 2>&1 || true
        
        # Try to read it back
        if security find-generic-password -a "cedar-test" -s "cedar-test-key" -w 2>/dev/null | grep -q "test-value"; then
            echo -e "${GREEN}✅ Keychain storage is working${NC}"
            # Clean up test entry
            security delete-generic-password -a "cedar-test" -s "cedar-test-key" 2>/dev/null || true
            return 0
        else
            echo -e "${YELLOW}⚠️  Keychain storage may not be available${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  macOS security command not found${NC}"
        return 1
    fi
}

# Function to test the backend server key endpoint
test_backend_endpoint() {
    echo "Testing backend server key endpoint..."
    
    # Start a temporary backend server if not running
    if ! curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "Backend server not running, skipping endpoint test"
        return 1
    fi
    
    # Test the config endpoint
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        http://localhost:8080/config/openai_key 2>/dev/null || echo "CURL_ERROR")
    
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    
    if [[ "$HTTP_STATUS" -eq 200 ]]; then
        echo -e "${GREEN}✅ Backend endpoint is accessible${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Backend endpoint returned $HTTP_STATUS${NC}"
        return 1
    fi
}

# Main validation flow
echo ""
echo "1. Checking environment variables..."
echo "================================================"

if [[ -n "$OPENAI_API_KEY" ]]; then
    echo -e "${GREEN}✅ OPENAI_API_KEY is set locally${NC}"
    echo "   Key: ${OPENAI_API_KEY:0:6}...${OPENAI_API_KEY: -4}"
    LOCAL_KEY=true
else
    echo -e "${YELLOW}⚠️  OPENAI_API_KEY not set locally${NC}"
    LOCAL_KEY=false
fi

if [[ -n "$CEDAR_KEY_URL" ]]; then
    echo -e "${GREEN}✅ CEDAR_KEY_URL is set: $CEDAR_KEY_URL${NC}"
else
    echo -e "${YELLOW}⚠️  CEDAR_KEY_URL not set, using default${NC}"
fi

if [[ -n "$APP_SHARED_TOKEN" ]]; then
    echo -e "${GREEN}✅ APP_SHARED_TOKEN is set${NC}"
else
    echo -e "${YELLOW}⚠️  APP_SHARED_TOKEN not set, using default${NC}"
fi

echo ""
echo "2. Testing key fetch from onrender server..."
echo "================================================"

if test_onrender_fetch; then
    ONRENDER_FETCH=true
else
    ONRENDER_FETCH=false
fi

echo ""
echo "3. Testing keychain storage..."
echo "================================================"

if test_keychain_storage; then
    KEYCHAIN_OK=true
else
    KEYCHAIN_OK=false
fi

echo ""
echo "4. Testing backend server endpoint..."
echo "================================================"

if test_backend_endpoint; then
    BACKEND_OK=true
else
    BACKEND_OK=false
fi

echo ""
echo "================================================"
echo "VALIDATION SUMMARY"
echo "================================================"

# Determine overall status
BUILD_OK=false

if [[ "$LOCAL_KEY" == true ]]; then
    echo -e "${GREEN}✅ Local API key available - BUILD CAN PROCEED${NC}"
    BUILD_OK=true
elif [[ "$ONRENDER_FETCH" == true ]]; then
    echo -e "${GREEN}✅ Can fetch API key from server - BUILD CAN PROCEED${NC}"
    BUILD_OK=true
else
    echo -e "${RED}❌ NO API KEY SOURCE AVAILABLE - BUILD SHOULD NOT PROCEED${NC}"
    echo ""
    echo "The app will not function without an API key!"
    echo ""
    echo "To fix this:"
    echo "1. Set OPENAI_API_KEY environment variable, OR"
    echo "2. Ensure the onrender server is accessible with proper token"
    echo ""
    echo "Current configuration:"
    echo "  CEDAR_KEY_URL: ${CEDAR_KEY_URL:-not set}"
    echo "  APP_SHARED_TOKEN: ${APP_SHARED_TOKEN:-not set}"
fi

echo ""
echo "Additional checks:"
[[ "$KEYCHAIN_OK" == true ]] && echo -e "  ${GREEN}✅ Keychain storage available${NC}" || echo -e "  ${YELLOW}⚠️  Keychain storage unavailable${NC}"
[[ "$BACKEND_OK" == true ]] && echo -e "  ${GREEN}✅ Backend endpoint working${NC}" || echo -e "  ${YELLOW}⚠️  Backend endpoint not accessible${NC}"

echo ""
echo "================================================"

# Exit with appropriate code
if [[ "$BUILD_OK" == true ]]; then
    echo -e "${GREEN}BUILD VALIDATION PASSED${NC}"
    exit 0
else
    echo -e "${RED}BUILD VALIDATION FAILED${NC}"
    exit 1
fi
