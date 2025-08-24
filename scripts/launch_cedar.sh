#!/bin/bash
# Cedar Desktop Launcher - Ensures API key is available

echo "🌲 Starting Cedar Desktop..."

# Check if API key is already set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "Fetching API key from Cedar server..."
    
    # Fetch the key from the Cedar server
    API_RESPONSE=$(curl -s -H "x-app-token: 403-298-09345-023495" https://cedar-notebook.onrender.com/v1/key)
    
    if [ $? -eq 0 ]; then
        # Extract the API key from the JSON response
        export OPENAI_API_KEY=$(echo "$API_RESPONSE" | grep -o '"openai_api_key":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$OPENAI_API_KEY" ]; then
            echo "✅ API key fetched successfully"
        else
            echo "⚠️ Failed to extract API key from response"
        fi
    else
        echo "⚠️ Failed to fetch API key from server"
    fi
else
    echo "✅ API key already configured"
fi

# Launch Cedar
if [ -f "/Applications/Cedar.app/Contents/MacOS/Cedar" ]; then
    echo "Launching Cedar from Applications..."
    /Applications/Cedar.app/Contents/MacOS/Cedar
elif [ -f "$HOME/Projects/cedarcli/target/release/cedar-egui" ]; then
    echo "Launching Cedar from development build..."
    $HOME/Projects/cedarcli/target/release/cedar-egui
else
    echo "❌ Cedar not found. Please install Cedar.app first."
    exit 1
fi
