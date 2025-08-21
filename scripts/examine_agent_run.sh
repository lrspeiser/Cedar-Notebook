#!/bin/bash

# Script to examine the agent loop execution for debugging
# Usage: ./examine_agent_run.sh [RUN_ID or latest]

RUNS_DIR="${CEDAR_RUNS_DIR:-$HOME/Library/Application Support/com.CedarAI.CedarAI/runs}"

if [ "$1" = "latest" ] || [ -z "$1" ]; then
    # Find the latest run
    RUN_ID=$(ls -t "$RUNS_DIR" | head -1)
else
    RUN_ID="$1"
fi

RUN_DIR="$RUNS_DIR/$RUN_ID"

if [ ! -d "$RUN_DIR" ]; then
    echo "Run directory not found: $RUN_DIR"
    exit 1
fi

echo "======================================"
echo "Examining Agent Run: $RUN_ID"
echo "Directory: $RUN_DIR"
echo "======================================"
echo

# Show directory structure
echo "📁 Run Directory Structure:"
find "$RUN_DIR" -type f -name "*.json" -o -name "*.jl" -o -name "*.log" | sort
echo

# Show cards (agent decisions)
echo "📋 Agent Decision Cards:"
if [ -d "$RUN_DIR/cards" ]; then
    for card in "$RUN_DIR/cards"/*.json; do
        if [ -f "$card" ]; then
            echo "  $(basename $card):"
            jq -r '.title + ": " + .summary' "$card" 2>/dev/null || cat "$card"
            echo
        fi
    done
fi

# Show tool outcomes
echo "🔧 Tool Execution Outcomes:"
for outcome in "$RUN_DIR"/*.outcome.json; do
    if [ -f "$outcome" ]; then
        echo "  $(basename $outcome):"
        jq -r '"    OK: " + (.ok|tostring) + "\n    Message: " + .message[:100]' "$outcome" 2>/dev/null
        echo
    fi
done

# Show Julia code if present
echo "📝 Julia Code Executed:"
if [ -f "$RUN_DIR/cell.jl" ]; then
    echo "  Content of cell.jl:"
    cat "$RUN_DIR/cell.jl" | sed 's/^/    /'
    echo
fi

# Show preview data if present
echo "📊 Preview Data:"
if [ -f "$RUN_DIR/preview.json" ]; then
    echo "  Preview JSON:"
    jq -r '.' "$RUN_DIR/preview.json" 2>/dev/null | head -20
    echo
fi

# Show any parquet files
echo "🗄️ Data Files:"
for pq in "$RUN_DIR"/*.parquet; do
    if [ -f "$pq" ]; then
        echo "  Found: $(basename $pq)"
    fi
done
