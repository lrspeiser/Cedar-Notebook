#!/bin/bash
# Debug test script for file ingestion with verbose logging

echo "========================================="
echo "Cedar File Ingestion Debug Test"
echo "========================================="

# Set debug environment variables
export CEDAR_DEBUG=1
export DEBUG=1
export RUST_LOG=debug,notebook_core=trace,notebook_server=trace

# Ensure we're in the right directory
cd "$(dirname "$0")/.." || exit 1

echo "Working directory: $(pwd)"
echo ""

# Kill any existing server
echo "Stopping any existing Cedar server..."
pkill -f "notebook_server" 2>/dev/null || true
sleep 1

# Rebuild with latest changes
echo "Building backend with debug logging..."
cargo build --release --bin notebook_server 2>&1 | tail -20

# Start the server with debug output
echo ""
echo "Starting Cedar server with debug logging..."
OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    CEDAR_DEBUG=1 \
    DEBUG=1 \
    cargo run --release --bin notebook_server 2>&1 | tee logs/debug_server.log &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
echo "Waiting for server to start..."
for i in {1..10}; do
    if curl -s http://localhost:8080/health > /dev/null; then
        echo "✅ Server is running"
        break
    fi
    echo "  Waiting... ($i/10)"
    sleep 1
done

# Run the test
echo ""
echo "========================================="
echo "Running file ingestion test"
echo "========================================="

# Use the enhanced test script
python tests/test_full_pipeline.py 2>&1 | tee logs/debug_test.log

# Show server logs
echo ""
echo "========================================="
echo "Recent server logs:"
echo "========================================="
tail -50 logs/debug_server.log | grep -E "\[JULIA\]|\[UPLOAD\]|\[DEBUG\]|ERROR|Parquet|DuckDB"

# Clean up
echo ""
echo "Stopping server..."
kill $SERVER_PID 2>/dev/null || true

echo ""
echo "========================================="
echo "Debug files created:"
echo "========================================="
echo "  - logs/debug_server.log (full server output)"
echo "  - logs/debug_test.log (test output)"
echo ""
echo "Check data/parquet/ for generated files:"
ls -la data/parquet/ 2>/dev/null || echo "  No parquet files found"
echo ""
echo "Check for DuckDB metadata:"
ls -la runs/metadata.duckdb 2>/dev/null || echo "  No metadata.duckdb found"
