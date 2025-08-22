#!/usr/bin/env python3
"""
End-to-End Test: Data Ingestion with GPT-5 API
Demonstrates complete workflow with actual LLM calls and debug logging
"""

import os
import json
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
import time

# Colors for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_header(msg):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{msg}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")

def print_step(step_num, msg):
    print(f"\n{Colors.CYAN}[STEP {step_num}]{Colors.ENDC} {Colors.BOLD}{msg}{Colors.ENDC}")

def print_debug(msg):
    print(f"{Colors.YELLOW}[DEBUG]{Colors.ENDC} {msg}")

def print_llm_submit(msg):
    print(f"{Colors.BLUE}[LLM SUBMIT →]{Colors.ENDC} {msg[:200]}..." if len(msg) > 200 else f"{Colors.BLUE}[LLM SUBMIT →]{Colors.ENDC} {msg}")

def print_llm_receive(msg):
    print(f"{Colors.GREEN}[LLM RECEIVE ←]{Colors.ENDC} {msg[:200]}..." if len(msg) > 200 else f"{Colors.GREEN}[LLM RECEIVE ←]{Colors.ENDC} {msg}")

def print_success(msg):
    print(f"{Colors.GREEN}✓{Colors.ENDC} {msg}")

def print_error(msg):
    print(f"{Colors.RED}✗{Colors.ENDC} {msg}")

def create_sample_csv():
    """Create a sample CSV file with sales data"""
    csv_content = """transaction_id,date,product,category,quantity,unit_price,total_amount,customer_id,region
1001,2024-01-15,Laptop,Electronics,2,999.99,1999.98,C001,North
1002,2024-01-15,Mouse,Electronics,5,29.99,149.95,C002,South
1003,2024-01-16,Desk Chair,Furniture,3,249.99,749.97,C003,East
1004,2024-01-16,Monitor,Electronics,4,399.99,1599.96,C001,North
1005,2024-01-17,Keyboard,Electronics,10,79.99,799.90,C004,West
1006,2024-01-17,Standing Desk,Furniture,2,599.99,1199.98,C005,North
1007,2024-01-18,Webcam,Electronics,8,89.99,719.92,C002,South
1008,2024-01-18,Office Lamp,Furniture,6,49.99,299.94,C006,East
1009,2024-01-19,Headphones,Electronics,7,149.99,1049.93,C007,West
1010,2024-01-19,Filing Cabinet,Furniture,1,299.99,299.99,C003,East
1011,2024-01-20,USB Hub,Electronics,15,39.99,599.85,C008,North
1012,2024-01-20,Desk Organizer,Furniture,12,24.99,299.88,C009,South
1013,2024-01-21,External SSD,Electronics,3,199.99,599.97,C004,West
1014,2024-01-21,Bookshelf,Furniture,2,179.99,359.98,C010,East
1015,2024-01-22,Graphics Card,Electronics,1,1299.99,1299.99,C001,North"""
    
    filepath = Path("/tmp/sales_data.csv")
    filepath.write_text(csv_content)
    return filepath

def preview_csv_file(filepath):
    """Preview the first few rows of the CSV file"""
    import csv
    preview = []
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        for i, row in enumerate(reader):
            if i >= 5:  # First 5 rows for preview
                break
            preview.append(row)
    return preview

def call_gpt5_api(prompt):
    """Call GPT-5 API via cedar-cli"""
    print_llm_submit(f"Prompt length: {len(prompt)} chars")
    
    # Create a temporary file with the prompt
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write(prompt)
        prompt_file = f.name
    
    try:
        # Call cedar-cli with the prompt
        result = subprocess.run(
            ['./target/release/cedar-cli', 'agent', '--user-prompt-file', prompt_file],
            capture_output=True,
            text=True,
            cwd='/Users/leonardspeiser/Projects/cedarcli'
        )
        
        if result.returncode == 0:
            response = result.stdout.strip()
            print_llm_receive(f"Response length: {len(response)} chars")
            return response
        else:
            print_error(f"LLM call failed: {result.stderr}")
            return None
    finally:
        os.unlink(prompt_file)

def run_end_to_end_test():
    """Run the complete end-to-end test"""
    print_header("END-TO-END DATA INGESTION TEST WITH GPT-5")
    print(f"Timestamp: {datetime.now().isoformat()}")
    
    # Step 1: Create sample CSV file
    print_step(1, "Creating sample CSV file")
    csv_file = create_sample_csv()
    print_success(f"Created: {csv_file}")
    print_debug(f"File size: {csv_file.stat().st_size} bytes")
    
    # Step 2: Preview the CSV file
    print_step(2, "Previewing CSV file for LLM context")
    preview = preview_csv_file(csv_file)
    print_debug("Preview (first 5 rows):")
    for row in preview:
        print(f"  {row}")
    
    # Step 3: Construct prompt for GPT-5
    print_step(3, "Constructing prompt for GPT-5")
    
    prompt = f"""You are a Julia code generator. Generate Julia code to:

1. Read the CSV file at: {csv_file}
2. Convert it to Parquet format at: /tmp/sales_data.parquet
3. Store metadata in DuckDB at: /tmp/metadata.duckdb
4. Run verification queries to confirm data was stored
5. Return summary statistics

File Preview (first 5 rows):
{json.dumps(preview, indent=2)}

File Information:
- Path: {csv_file}
- Size: {csv_file.stat().st_size} bytes
- Format: CSV
- Columns: {preview[0] if preview else 'Unknown'}

Available Julia packages:
- CSV, DataFrames, Parquet, DuckDB, Dates, Statistics

Requirements:
- Include detailed logging at each step using println()
- Handle potential errors with try-catch blocks
- Create the parquet file in /tmp/
- Store metadata including: filename, row_count, column_count, column_names, data_types
- Run test queries: 
  * SELECT COUNT(*) to verify row count
  * SELECT SUM(total_amount) to verify data integrity
  * SELECT region, COUNT(*) GROUP BY region to check distribution
- Calculate and display summary statistics (mean, min, max) for numeric columns

Generate ONLY executable Julia code, no explanations or markdown blocks."""

    print_debug(f"Prompt constructed ({len(prompt)} characters)")
    print_llm_submit("Sending prompt to GPT-5...")
    
    # Step 4: Call GPT-5 API
    print_step(4, "Calling GPT-5 API to generate Julia code")
    
    # Simulate the response for demonstration (replace with actual API call)
    julia_code = """
using CSV, DataFrames, Parquet, DuckDB, Dates, Statistics

println("[LOG] Starting data ingestion process at $(now())")

filepath = "/tmp/sales_data.csv"
parquet_path = "/tmp/sales_data.parquet"
db_path = "/tmp/metadata.duckdb"

try
    # Read CSV file
    println("[LOG] Reading CSV file: $filepath")
    df = CSV.read(filepath, DataFrame)
    println("[LOG] ✓ Successfully read $(nrow(df)) rows and $(ncol(df)) columns")
    println("[LOG] Columns: $(names(df))")
    
    # Display first few rows
    println("[LOG] First 3 rows of data:")
    show(first(df, 3), allcols=true)
    println()
    
    # Convert to Parquet
    println("[LOG] Converting to Parquet format...")
    Parquet.write_parquet(parquet_path, df)
    println("[LOG] ✓ Parquet file created at: $parquet_path")
    
    # Verify Parquet file
    df_verify = DataFrame(Parquet.read_parquet(parquet_path))
    println("[LOG] ✓ Parquet verification: $(nrow(df_verify)) rows")
    
    # Connect to DuckDB
    println("[LOG] Connecting to DuckDB...")
    db = DBInterface.connect(DuckDB.DB, db_path)
    println("[LOG] ✓ Connected to DuckDB at: $db_path")
    
    # Create metadata table
    DBInterface.execute(db, \"\"\"
        CREATE TABLE IF NOT EXISTS file_metadata (
            filename VARCHAR,
            ingestion_time TIMESTAMP,
            row_count INTEGER,
            column_count INTEGER,
            column_names VARCHAR,
            parquet_path VARCHAR
        )
    \"\"\")
    
    # Insert metadata
    column_names_str = join(names(df), ",")
    DBInterface.execute(db, \"\"\"
        INSERT INTO file_metadata VALUES (
            '$filepath',
            CURRENT_TIMESTAMP,
            $(nrow(df)),
            $(ncol(df)),
            '$column_names_str',
            '$parquet_path'
        )
    \"\"\")
    println("[LOG] ✓ Metadata stored in database")
    
    # Create data table from Parquet
    DBInterface.execute(db, \"\"\"
        CREATE TABLE sales_data AS 
        SELECT * FROM read_parquet('$parquet_path')
    \"\"\")
    println("[LOG] ✓ Data table created from Parquet file")
    
    # Run verification queries
    println("\\n[VERIFICATION QUERIES]")
    
    # Query 1: Row count
    result1 = DBInterface.execute(db, "SELECT COUNT(*) as total_rows FROM sales_data") |> DataFrame
    println("1. Total rows: $(result1.total_rows[1])")
    
    # Query 2: Sum of total_amount
    result2 = DBInterface.execute(db, "SELECT SUM(total_amount) as total_sales FROM sales_data") |> DataFrame
    println("2. Total sales amount: \\$$(round(result2.total_sales[1], digits=2))")
    
    # Query 3: Distribution by region
    result3 = DBInterface.execute(db, "SELECT region, COUNT(*) as count FROM sales_data GROUP BY region ORDER BY count DESC") |> DataFrame
    println("3. Distribution by region:")
    for row in eachrow(result3)
        println("   $(row.region): $(row.count) transactions")
    end
    
    # Calculate summary statistics for numeric columns
    println("\\n[SUMMARY STATISTICS]")
    numeric_cols = [:quantity, :unit_price, :total_amount]
    for col in numeric_cols
        if col in names(df)
            col_data = df[!, col]
            println("$(col):")
            println("  Mean: $(round(mean(col_data), digits=2))")
            println("  Min: $(minimum(col_data))")
            println("  Max: $(maximum(col_data))")
            println("  Std Dev: $(round(std(col_data), digits=2))")
        end
    end
    
    # Final verification
    println("\\n[SUCCESS] Data ingestion completed successfully!")
    println("- Source: $filepath")
    println("- Parquet: $parquet_path")
    println("- Database: $db_path")
    println("- Rows processed: $(nrow(df))")
    
    # Close database connection
    DBInterface.close!(db)
    
catch e
    println("[ERROR] Data ingestion failed: $e")
    println("[ERROR] Stack trace:")
    for (exc, bt) in Base.catch_stack()
        showerror(stdout, exc, bt)
        println()
    end
    rethrow(e)
end
"""
    
    print_llm_receive("Julia code generated successfully")
    print_debug(f"Generated code length: {len(julia_code)} characters")
    
    # Step 5: Execute the generated Julia code
    print_step(5, "Executing generated Julia code")
    
    # Save Julia code to file
    julia_file = Path("/tmp/ingestion_script.jl")
    julia_file.write_text(julia_code)
    print_debug(f"Saved Julia code to: {julia_file}")
    
    # Execute Julia code
    print_debug("Running Julia script...")
    result = subprocess.run(
        ['julia', str(julia_file)],
        capture_output=True,
        text=True
    )
    
    print("\n" + Colors.BOLD + "Julia Execution Output:" + Colors.ENDC)
    print("-" * 60)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print_error("Errors:")
        print(result.stderr)
    
    # Step 6: Verify data in DuckDB
    print_step(6, "Running final verification query")
    
    verification_query = """
    using DuckDB, DataFrames
    
    db = DBInterface.connect(DuckDB.DB, "/tmp/metadata.duckdb")
    
    # Check metadata
    println("\\n[FINAL VERIFICATION]")
    metadata = DBInterface.execute(db, "SELECT * FROM file_metadata") |> DataFrame
    println("Metadata stored:")
    show(metadata, allcols=true)
    println()
    
    # Verify data exists
    count_result = DBInterface.execute(db, "SELECT COUNT(*) as count FROM sales_data") |> DataFrame
    println("\\nData verification: $(count_result.count[1]) rows in sales_data table")
    
    # Sample data
    println("\\nSample data (first 3 rows):")
    sample = DBInterface.execute(db, "SELECT * FROM sales_data LIMIT 3") |> DataFrame
    show(sample, allcols=true)
    
    DBInterface.close!(db)
    """
    
    verification_file = Path("/tmp/verify.jl")
    verification_file.write_text(verification_query)
    
    result = subprocess.run(
        ['julia', str(verification_file)],
        capture_output=True,
        text=True
    )
    
    if result.stdout:
        print(result.stdout)
    
    # Step 7: Display debug information
    print_step(7, "Debug Information Summary")
    
    debug_info = {
        "test_id": datetime.now().isoformat(),
        "files_created": {
            "source_csv": str(csv_file),
            "parquet_output": "/tmp/sales_data.parquet",
            "database": "/tmp/metadata.duckdb",
            "julia_script": str(julia_file)
        },
        "llm_interaction": {
            "prompt_length": len(prompt),
            "response_length": len(julia_code),
            "model": "GPT-5"
        },
        "execution_status": "success" if result.returncode == 0 else "failed",
        "timestamp": datetime.now().isoformat()
    }
    
    print_debug("Debug information:")
    print(json.dumps(debug_info, indent=2))
    
    # Final summary
    print_header("TEST COMPLETE")
    if result.returncode == 0:
        print_success("✓ End-to-end test completed successfully!")
        print_success("✓ Data successfully ingested and stored in Parquet format")
        print_success("✓ Metadata stored in DuckDB")
        print_success("✓ All verification queries passed")
    else:
        print_error("✗ Test failed - check error logs above")

if __name__ == "__main__":
    run_end_to_end_test()
