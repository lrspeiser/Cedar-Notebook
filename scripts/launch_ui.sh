#!/bin/bash

# Launch script for Cedar Agent Loop Visualizer

echo "🌲 Cedar Agent Loop Visualizer"
echo "=============================="
echo

# Check if the server is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "⚠️  Backend server not detected on port 8080"
    echo "Starting the server..."
    
    # Start the server in the background
    cd "$(dirname "$0")/.."
    ./target/release/notebook_server &
    SERVER_PID=$!
    
    echo "Server started with PID: $SERVER_PID"
    echo "Waiting for server to be ready..."
    
    # Wait for server to be healthy
    for i in {1..10}; do
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            echo "✓ Server is ready!"
            break
        fi
        sleep 1
    done
else
    echo "✓ Backend server is already running"
fi

echo
echo "Opening web UI..."

# Determine the OS and open the browser
UI_FILE="$(dirname "$0")/../apps/web-ui/app.html"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    open "$UI_FILE"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    xdg-open "$UI_FILE"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    # Windows
    start "$UI_FILE"
else
    echo "Please open the following file in your browser:"
    echo "  $UI_FILE"
fi

echo
echo "UI launched! The visualizer should now be open in your browser."
echo
echo "Features:"
echo "  • Real-time execution flow visualization"
echo "  • Step-by-step agent loop breakdown"
echo "  • View generated artifacts and data"
echo "  • Interactive query execution"
echo
echo "To use the full agent loop functionality:"
echo "  1. Enter your OpenAI API key in the Configuration section"
echo "  2. Make sure the backend server is running (port 8080)"
echo "  3. Enter a query and click 'Execute Query'"
echo
echo "Press Ctrl+C to stop the server (if started by this script)"

# If we started the server, wait for it
if [ ! -z "$SERVER_PID" ]; then
    trap "kill $SERVER_PID 2>/dev/null; echo 'Server stopped'" EXIT
    wait $SERVER_PID
fi
