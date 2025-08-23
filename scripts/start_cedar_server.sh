#!/bin/bash

echo "Starting Cedar Server..."
echo "========================"

# Load environment variables from .env if it exists
if [ -f .env ]; then
    echo "Loading .env file..."
    export $(cat .env | grep -v '^#' | xargs)
fi

# IMPORTANT: Fetch API key from onrender server if configured
# See docs/openai-key-flow.md and README.md for complete documentation
# Default to onrender server if no local key is set
if [ -z "$OPENAI_API_KEY" ]; then
    # Use configured values or defaults for onrender
    CEDAR_KEY_URL=${CEDAR_KEY_URL:-"https://cedar-notebook.onrender.com/v1/key"}
    APP_SHARED_TOKEN=${APP_SHARED_TOKEN:-"403-298-09345-023495"}
    
    echo "Fetching API key from: $CEDAR_KEY_URL"
    RESPONSE=$(curl -s -H "x-app-token: $APP_SHARED_TOKEN" "$CEDAR_KEY_URL")
    
    if [ $? -eq 0 ]; then
        # Extract the API key from JSON response
        API_KEY=$(echo "$RESPONSE" | grep -o '"openai_api_key":"[^"]*' | cut -d'"' -f4)
        
        if [ -n "$API_KEY" ]; then
            export OPENAI_API_KEY="$API_KEY"
            echo "✅ API key fetched from server"
        else
            echo "⚠️  Failed to extract API key from server response"
        fi
    else
        echo "⚠️  Failed to fetch API key from server"
    fi
fi

# Check if API key is available from any source
if [ -z "$OPENAI_API_KEY" ]; then
    # Try to get from keychain (macOS)
    if command -v security &> /dev/null; then
        echo "Trying to get API key from keychain..."
        KEYCHAIN_KEY=$(security find-generic-password -s "cedar-cli" -a "OPENAI_API_KEY" -w 2>/dev/null)
        if [ -n "$KEYCHAIN_KEY" ]; then
            export OPENAI_API_KEY="$KEYCHAIN_KEY"
            echo "✅ API key loaded from keychain"
        fi
    fi
fi

# Check if API key is available from config file
if [ -z "$OPENAI_API_KEY" ]; then
    CONFIG_FILE="$HOME/Library/Preferences/com.CedarAI.cedar-cli/.env"
    if [ -f "$CONFIG_FILE" ]; then
        echo "Loading API key from config file..."
        source "$CONFIG_FILE"
        if [ -n "$OPENAI_API_KEY" ]; then
            echo "✅ API key loaded from config file"
        fi
    fi
fi

# Final check
if [ -z "$OPENAI_API_KEY" ]; then
    echo ""
    echo "❌ ERROR: No OpenAI API key found!"
    echo ""
    echo "Please set your API key using one of these methods:"
    echo "1. Set OPENAI_API_KEY in your .env file"
    echo "2. Export OPENAI_API_KEY=your-key-here"
    echo "3. Configure CEDAR_KEY_URL and APP_SHARED_TOKEN for server-based key"
    echo ""
    echo "For more info, see README.md section: 'OpenAI configuration and key flow'"
    exit 1
fi

echo ""
echo "✅ API key configured"
echo "📦 Starting notebook server on http://localhost:8080"
echo ""

# Build if needed
if [ ! -f "target/release/notebook_server" ]; then
    echo "Building notebook_server..."
    cargo build --release --bin notebook_server
fi

# Run the server with the API key set
exec cargo run --release --bin notebook_server
