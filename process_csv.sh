#!/bin/bash

# Cedar CSV Processing Script
# This script processes CSV files using their full paths

if [ $# -eq 0 ]; then
    echo "Usage: $0 <csv_file_path> [query]"
    echo "Example: $0 /path/to/file.csv 'Summarize this data'"
    exit 1
fi

CSV_FILE="$1"
QUERY="${2:-Analyze and summarize this CSV file}"

# Check if file exists
if [ ! -f "$CSV_FILE" ]; then
    echo "Error: File not found: $CSV_FILE"
    exit 1
fi

# Get absolute path
CSV_PATH=$(realpath "$CSV_FILE")
echo "Processing file: $CSV_PATH"

# Create a query that includes the full file path
FULL_QUERY="Please analyze the CSV file located at: $CSV_PATH

$QUERY

Use Julia to:
1. Read the CSV file from the exact path: $CSV_PATH
2. Load it into a DataFrame
3. Provide a summary including:
   - Number of rows and columns
   - Column names and types
   - Basic statistics
   - Any interesting patterns or insights"

# Submit to Cedar backend
echo "Submitting query to Cedar..."
curl -X POST http://localhost:8080/commands/submit_query \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "prompt": "$FULL_QUERY"
}
EOF

echo ""
echo "Query submitted. Check the Cedar web interface for results."
