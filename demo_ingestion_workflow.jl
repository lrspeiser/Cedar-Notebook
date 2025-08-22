# Demo: Complete Data Ingestion Workflow
# This demonstrates how the system works without using actual API keys

using CSV, DataFrames, XLSX, Dates

println("=== Data Ingestion Workflow Demo ===\n")

# Step 1: File Preview (what gets passed to LLM)
function preview_file(filepath)
    println("📁 STEP 1: Previewing file for LLM context")
    println("File: $filepath")
    
    try
        # Try to read first 30 rows
        if endswith(filepath, ".csv")
            df = CSV.read(filepath, DataFrame; limit=30)
            
            preview_info = Dict(
                "file_path" => filepath,
                "file_size" => filesize(filepath),
                "shape_preview" => size(df),
                "columns" => names(df),
                "dtypes" => [string(eltype(df[!, col])) for col in names(df)],
                "first_5_rows" => first(df, 5)
            )
            
            println("✅ Preview successful:")
            println("  - Rows in preview: $(size(df, 1))")
            println("  - Columns: $(join(names(df), ", "))")
            return preview_info
            
        elseif endswith(filepath, ".xlsx")
            xf = XLSX.readxlsx(filepath)
            sheet = XLSX.sheetnames(xf)[1]
            data = XLSX.readtable(filepath, sheet; infer_eltypes=true)
            df = DataFrame(data)
            
            preview_info = Dict(
                "file_path" => filepath,
                "file_size" => filesize(filepath),
                "sheets" => XLSX.sheetnames(xf),
                "shape_preview" => size(first(df, 30)),
                "columns" => names(df),
                "first_5_rows" => first(df, 5)
            )
            
            println("✅ Excel preview successful")
            return preview_info
        end
        
    catch e
        error_msg = string(e)
        println("❌ Preview failed: $error_msg")
        return Dict("error" => error_msg, "file" => filepath)
    end
end

# Step 2: LLM Prompt Construction (what gets sent to LLM)
function construct_llm_prompt(preview_info, target_db)
    println("\n📝 STEP 2: Constructing LLM prompt")
    
    prompt = """
    Generate Julia code to process this data file:
    
    File Information:
    - Path: $(preview_info["file_path"])
    - Size: $(preview_info["file_size"]) bytes
    - Shape: $(preview_info["shape_preview"])
    - Columns: $(join(preview_info["columns"], ", "))
    
    Task Requirements:
    1. Read the complete file
    2. Convert to Parquet format
    3. Store metadata in DuckDB at: $target_db
    4. Run test queries to verify
    5. Log each step with detailed info
    
    Available packages: CSV, DataFrames, Parquet, XLSX, DuckDB
    """
    
    println("📋 Prompt length: $(length(prompt)) characters")
    return prompt
end

# Step 3: Simulated LLM Response (what LLM would generate)
function simulate_llm_generation(prompt)
    println("\n🤖 STEP 3: LLM generates Julia code")
    
    # This is what the LLM would generate based on the prompt
    generated_code = """
    # Auto-generated Julia code for data ingestion
    using CSV, DataFrames, Parquet, DuckDB
    
    println("[LOG] Starting data ingestion process...")
    
    # Read the source file
    filepath = "test_data.csv"
    println("[LOG] Reading file: \$filepath")
    
    try
        df = CSV.read(filepath, DataFrame)
        println("[LOG] ✅ File read successfully")
        println("[LOG] Shape: \$(size(df))")
        println("[LOG] Columns: \$(names(df))")
        
        # Convert to Parquet
        parquet_path = replace(filepath, ".csv" => ".parquet")
        println("[LOG] Converting to Parquet: \$parquet_path")
        
        Parquet.write_parquet(parquet_path, df)
        println("[LOG] ✅ Parquet file created")
        
        # Store metadata in DuckDB
        db = DBInterface.connect(DuckDB.DB, "metadata.duckdb")
        println("[LOG] Connected to DuckDB")
        
        # Create metadata table if not exists
        DBInterface.execute(db, \"\"\"
            CREATE TABLE IF NOT EXISTS file_metadata (
                filename VARCHAR,
                row_count INTEGER,
                column_count INTEGER,
                columns VARCHAR,
                ingestion_time TIMESTAMP,
                parquet_path VARCHAR
            )
        \"\"\")
        
        # Insert metadata
        DBInterface.execute(db, \"\"\"
            INSERT INTO file_metadata VALUES (
                '\$filepath',
                \$(nrow(df)),
                \$(ncol(df)),
                '\$(join(names(df), ","))',
                CURRENT_TIMESTAMP,
                '\$parquet_path'
            )
        \"\"\")
        println("[LOG] ✅ Metadata stored in DuckDB")
        
        # Run test query
        result = DBInterface.execute(db, "SELECT * FROM file_metadata") |> DataFrame
        println("[LOG] Test query result:")
        println(result)
        
        # Verify Parquet file
        df_verify = Parquet.read_parquet(parquet_path) |> DataFrame
        println("[LOG] ✅ Verification: Parquet has \$(nrow(df_verify)) rows")
        
        println("[SUCCESS] Data ingestion completed successfully!")
        
    catch e
        println("[ERROR] Failed: \$e")
        # This error would be passed back to LLM for correction
        rethrow(e)
    end
    """
    
    println("📄 Generated $(length(generated_code)) characters of Julia code")
    return generated_code
end

# Step 4: Execute and capture debug info
function execute_with_debug(julia_code)
    println("\n⚙️ STEP 4: Executing generated code with debug capture")
    
    debug_info = Dict(
        "timestamp" => now(),
        "attempt" => 1,
        "code_length" => length(julia_code)
    )
    
    try
        # Execute the code (in real system, this would be eval() or run())
        println("[DEBUG] Executing Julia code...")
        
        # Simulate execution logs
        logs = """
        [LOG] Starting data ingestion process...
        [LOG] Reading file: test_data.csv
        [LOG] ✅ File read successfully
        [LOG] Shape: (35, 6)
        [LOG] Columns: ["id", "name", "department", "salary", "hire_date", "active"]
        [LOG] Converting to Parquet: test_data.parquet
        [LOG] ✅ Parquet file created
        [LOG] Connected to DuckDB
        [LOG] ✅ Metadata stored in DuckDB
        [LOG] Test query result:
        │ filename      │ row_count │ column_count │ columns                                    │
        │ test_data.csv │ 35        │ 6            │ id,name,department,salary,hire_date,active │
        [LOG] ✅ Verification: Parquet has 35 rows
        [SUCCESS] Data ingestion completed successfully!
        """
        
        debug_info["status"] = "success"
        debug_info["logs"] = logs
        debug_info["rows_processed"] = 35
        
        println(logs)
        
    catch e
        # If error, capture for LLM retry
        error_msg = string(e)
        debug_info["status"] = "error"
        debug_info["error"] = error_msg
        
        println("❌ Execution failed: $error_msg")
        println("🔄 Would send error back to LLM for retry...")
        
        # Construct retry prompt
        retry_prompt = """
        The previous code failed with error:
        $error_msg
        
        Please fix the code. Original file info:
        [Include preview_info here]
        """
        
        debug_info["retry_prompt"] = retry_prompt
    end
    
    return debug_info
end

# Step 5: Store complete debug information
function store_debug_info(debug_info)
    println("\n💾 STEP 5: Storing debug information")
    
    # In real system, this would go to database
    debug_record = Dict(
        "ingestion_id" => rand(1000:9999),
        "timestamp" => debug_info["timestamp"],
        "attempts" => [debug_info],
        "final_status" => debug_info["status"],
        "total_rows" => get(debug_info, "rows_processed", 0),
        "logs" => debug_info["logs"]
    )
    
    println("📊 Debug Summary:")
    println("  - Ingestion ID: $(debug_record["ingestion_id"])")
    println("  - Status: $(debug_record["final_status"])")
    println("  - Rows processed: $(debug_record["total_rows"])")
    println("  - Debug info stored for analysis")
    
    return debug_record
end

# Main workflow demonstration
function demo_complete_workflow()
    println("\n" * "="^50)
    println("COMPLETE DATA INGESTION WORKFLOW DEMO")
    println("="^50 * "\n")
    
    # Configuration
    source_file = "test_data.csv"
    target_db = "metadata.duckdb"
    
    println("Configuration:")
    println("  📁 Source: $source_file")
    println("  🗄️ Target DB: $target_db")
    println()
    
    # Step 1: Preview file
    preview_info = preview_file(source_file)
    
    # Step 2: Create LLM prompt
    prompt = construct_llm_prompt(preview_info, target_db)
    
    # Step 3: LLM generates code
    generated_code = simulate_llm_generation(prompt)
    
    # Step 4: Execute with debug capture
    debug_info = execute_with_debug(generated_code)
    
    # Step 5: Store debug info
    final_record = store_debug_info(debug_info)
    
    println("\n" * "="^50)
    println("✅ WORKFLOW COMPLETE")
    println("="^50)
    
    return final_record
end

# Run the demo
# demo_complete_workflow()

println("""

To run the complete workflow demo, execute:
  demo_complete_workflow()

This will show:
1. How files are previewed for the LLM
2. How prompts are constructed with file metadata
3. How the LLM generates Julia code
4. How execution is monitored and errors captured
5. How debug information is stored

All without using actual API keys - the LLM interaction is simulated.
""")
