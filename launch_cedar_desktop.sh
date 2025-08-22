#!/bin/bash

# Cedar Desktop Launcher with API Key Management
# This script ensures the Cedar server has the OpenAI API key configured

echo "🚀 Starting Cedar Desktop..."
echo "================================"

# Check if OPENAI_API_KEY is already set
if [ -n "$OPENAI_API_KEY" ]; then
    echo "✅ API key already configured in environment"
else
    # Try to load from .env file in app directory
    APP_DIR="$(dirname "$0")"
    if [ -f "$APP_DIR/.env" ]; then
        echo "Loading API key from .env file..."
        export $(cat "$APP_DIR/.env" | grep -v '^#' | xargs)
    fi
    
    # Try keychain (macOS)
    if [ -z "$OPENAI_API_KEY" ]; then
        if command -v security &> /dev/null; then
            echo "Checking macOS keychain for API key..."
            KEYCHAIN_KEY=$(security find-generic-password -s "cedar-cli" -a "OPENAI_API_KEY" -w 2>/dev/null)
            if [ -n "$KEYCHAIN_KEY" ]; then
                export OPENAI_API_KEY="$KEYCHAIN_KEY"
                echo "✅ API key loaded from keychain"
            fi
        fi
    fi
    
    # Try user config directory
    if [ -z "$OPENAI_API_KEY" ]; then
        CONFIG_FILE="$HOME/Library/Preferences/com.CedarAI.cedar-cli/.env"
        if [ -f "$CONFIG_FILE" ]; then
            echo "Loading API key from config file..."
            source "$CONFIG_FILE"
        fi
    fi
fi

# Final check
if [ -z "$OPENAI_API_KEY" ]; then
    echo ""
    echo "⚠️  WARNING: No OpenAI API key found!"
    echo ""
    echo "Cedar will not be able to process queries without an API key."
    echo ""
    echo "To set your API key:"
    echo "1. Create a .env file next to this app with: OPENAI_API_KEY=your-key"
    echo "2. Or set it in your shell: export OPENAI_API_KEY=your-key"
    echo "3. Or save it to keychain: security add-generic-password -s 'cedar-cli' -a 'OPENAI_API_KEY' -w 'your-key'"
    echo ""
    echo "Press Enter to continue anyway, or Ctrl+C to exit..."
    read
fi

# Launch the Cedar Desktop app
echo "📱 Launching Cedar Desktop..."
open -a "cedar-desktop"
