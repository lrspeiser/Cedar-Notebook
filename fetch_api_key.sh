#!/bin/bash

# Script to fetch OpenAI API key from OnRender server and save to local .env
# This allows testing the Cedar CLI with the real GPT-5 API

set -e

# OnRender API endpoint for fetching secrets
# You'll need to update this with your actual OnRender service URL
ONRENDER_SERVICE_URL="${ONRENDER_SERVICE_URL:-https://your-service.onrender.com}"
ONRENDER_API_KEY="${ONRENDER_API_KEY:-}"

# Function to fetch the API key from OnRender
fetch_api_key_from_onrender() {
    echo "Fetching OpenAI API key from OnRender..."
    
    # Check if we have the OnRender API key
    if [ -z "$ONRENDER_API_KEY" ]; then
        echo "Error: ONRENDER_API_KEY is not set. Please set it first:"
        echo "  export ONRENDER_API_KEY='your-onrender-api-key'"
        exit 1
    fi
    
    # Make API call to OnRender to get environment variables
    # This assumes you have an endpoint that returns environment variables
    response=$(curl -s -H "Authorization: Bearer $ONRENDER_API_KEY" \
                    "${ONRENDER_SERVICE_URL}/api/env" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to OnRender service"
        exit 1
    fi
    
    # Extract the OpenAI API key from the response
    # Adjust the jq query based on your actual API response format
    openai_key=$(echo "$response" | jq -r '.OPENAI_API_KEY // empty')
    
    if [ -z "$openai_key" ]; then
        echo "Error: Could not extract OPENAI_API_KEY from OnRender response"
        echo "Response was: $response"
        exit 1
    fi
    
    echo "$openai_key"
}

# Alternative: SSH into OnRender and get the key directly
fetch_api_key_via_ssh() {
    echo "Fetching OpenAI API key via SSH..."
    
    # You'll need to configure your OnRender SSH details
    ONRENDER_SSH_HOST="${ONRENDER_SSH_HOST:-your-service.onrender.com}"
    ONRENDER_SSH_USER="${ONRENDER_SSH_USER:-render}"
    
    # SSH into the server and print the environment variable
    openai_key=$(ssh -o ConnectTimeout=10 \
                     "${ONRENDER_SSH_USER}@${ONRENDER_SSH_HOST}" \
                     'echo $OPENAI_API_KEY' 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$openai_key" ]; then
        echo "Error: Failed to fetch API key via SSH"
        exit 1
    fi
    
    echo "$openai_key"
}

# Alternative: Use Render CLI to get environment variables
fetch_api_key_via_render_cli() {
    echo "Fetching OpenAI API key via Render CLI..."
    
    # Check if render CLI is installed
    if ! command -v render &> /dev/null; then
        echo "Error: Render CLI is not installed"
        echo "Install it with: brew install render/tap/render"
        exit 1
    fi
    
    # Get the service ID (you'll need to set this)
    SERVICE_ID="${RENDER_SERVICE_ID:-}"
    
    if [ -z "$SERVICE_ID" ]; then
        echo "Error: RENDER_SERVICE_ID is not set"
        echo "You can find it in your Render dashboard"
        exit 1
    fi
    
    # Fetch environment variables using render CLI
    openai_key=$(render env:get OPENAI_API_KEY --service "$SERVICE_ID" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$openai_key" ]; then
        echo "Error: Failed to fetch API key via Render CLI"
        exit 1
    fi
    
    echo "$openai_key"
}

# Simple method: Direct API call using Render's API
fetch_api_key_direct() {
    echo "Fetching OpenAI API key using Render API..."
    
    # You need to set your Render API key
    # Get it from: https://dashboard.render.com/account/settings
    RENDER_API_KEY="${RENDER_API_KEY:-}"
    
    if [ -z "$RENDER_API_KEY" ]; then
        echo "Error: RENDER_API_KEY is not set"
        echo "Get your API key from: https://dashboard.render.com/account/settings"
        echo "Then run: export RENDER_API_KEY='your-key'"
        exit 1
    fi
    
    # Get service ID - you can find this in your Render dashboard URL
    # or by running: render services list
    SERVICE_ID="${RENDER_SERVICE_ID:-}"
    
    if [ -z "$SERVICE_ID" ]; then
        echo "Error: RENDER_SERVICE_ID is not set"
        echo "Find your service ID in the Render dashboard URL"
        echo "Then run: export RENDER_SERVICE_ID='srv-...'"
        exit 1
    fi
    
    # Fetch environment variables from Render API
    response=$(curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
                    "https://api.render.com/v1/services/$SERVICE_ID/env-vars" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to Render API"
        exit 1
    fi
    
    # Extract the OpenAI API key from the response
    openai_key=$(echo "$response" | jq -r '.[] | select(.key=="OPENAI_API_KEY") | .value // empty')
    
    if [ -z "$openai_key" ]; then
        echo "Error: Could not find OPENAI_API_KEY in service environment"
        echo "Available keys:"
        echo "$response" | jq -r '.[].key' 2>/dev/null
        exit 1
    fi
    
    echo "$openai_key"
}

# Main execution
main() {
    # Choose the method to fetch the API key
    # Try methods in order of preference:
    
    # Method 1: Direct Render API (simplest, recommended)
    if [ -n "$RENDER_API_KEY" ] && [ -n "$RENDER_SERVICE_ID" ]; then
        API_KEY=$(fetch_api_key_direct)
    # Method 2: Via Render CLI (if logged in)
    elif command -v render &> /dev/null && render config &> /dev/null; then
        API_KEY=$(fetch_api_key_via_render_cli)
    else
        echo "Please set up one of the following:"
        echo "1. Set RENDER_API_KEY and RENDER_SERVICE_ID environment variables"
        echo "2. Log in to Render CLI: render login"
        echo "3. Configure SSH access to your OnRender service"
        exit 1
    fi
    
    if [ -z "$API_KEY" ]; then
        echo "Error: Failed to fetch API key"
        exit 1
    fi
    
    # Create or update .env file
    ENV_FILE=".env"
    
    # Backup existing .env if it exists
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${ENV_FILE}.backup"
        echo "Backed up existing .env to .env.backup"
    fi
    
    # Check if OPENAI_API_KEY already exists in .env
    if [ -f "$ENV_FILE" ] && grep -q "^OPENAI_API_KEY=" "$ENV_FILE"; then
        # Update existing key
        sed -i '' "s/^OPENAI_API_KEY=.*/OPENAI_API_KEY=$API_KEY/" "$ENV_FILE"
        echo "Updated OPENAI_API_KEY in .env"
    else
        # Add new key
        echo "OPENAI_API_KEY=$API_KEY" >> "$ENV_FILE"
        echo "Added OPENAI_API_KEY to .env"
    fi
    
    # Also export it for immediate use
    export OPENAI_API_KEY="$API_KEY"
    
    echo "Successfully fetched and saved OpenAI API key"
    echo "You can now run: source .env && ./target/release/cedar-cli agent --user-prompt \"what is 2+2\""
}

# Run the main function
main "$@"
