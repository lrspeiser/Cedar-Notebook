#!/bin/bash

# Simple script to set up OpenAI API key for testing Cedar CLI

echo "Setting up OpenAI API key for Cedar CLI testing"
echo "================================================"
echo ""

# Check if API key is provided as argument
if [ -n "$1" ]; then
    API_KEY="$1"
else
    # Prompt for API key
    echo "Please enter your OpenAI API key:"
    echo "(You can get it from: https://platform.openai.com/api-keys)"
    read -s API_KEY
    echo ""
fi

if [ -z "$API_KEY" ]; then
    echo "Error: No API key provided"
    exit 1
fi

# Validate the key format (basic check)
if [[ ! "$API_KEY" =~ ^sk-[a-zA-Z0-9]{48}$ ]]; then
    echo "Warning: API key doesn't match expected format (sk-...)"
    echo "Continuing anyway..."
fi

# Create or update .env file
ENV_FILE=".env"

# Backup existing .env if it exists
if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "${ENV_FILE}.backup"
    echo "✓ Backed up existing .env to .env.backup"
fi

# Check if OPENAI_API_KEY already exists in .env
if [ -f "$ENV_FILE" ] && grep -q "^OPENAI_API_KEY=" "$ENV_FILE"; then
    # Update existing key
    sed -i '' "s/^OPENAI_API_KEY=.*/OPENAI_API_KEY=$API_KEY/" "$ENV_FILE"
    echo "✓ Updated OPENAI_API_KEY in .env"
else
    # Add new key
    echo "OPENAI_API_KEY=$API_KEY" >> "$ENV_FILE"
    echo "✓ Added OPENAI_API_KEY to .env"
fi

echo ""
echo "Setup complete! Your API key has been saved to .env"
echo ""
echo "To test the Cedar CLI agent, run:"
echo "  source .env && ./target/release/cedar-cli agent --user-prompt \"what is 2+2\""
echo ""
echo "To test with debug output:"
echo "  source .env && CEDAR_LOG_LLM_JSON=1 ./target/release/cedar-cli agent --user-prompt \"what is 2+2\""
