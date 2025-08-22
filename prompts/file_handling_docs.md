# File Type Handling in Julia for Cedar

## Supported File Types and Reading Methods

### CSV Files (.csv, .tsv, .txt)
```julia
using CSV, DataFrames
# Basic CSV reading
df = CSV.read("file.csv", DataFrame)
# With options
df = CSV.read("file.tsv", DataFrame; delim='\t', header=true, missingstring="NA")
# Handle encoding issues
df = CSV.read("file.csv", DataFrame; stringtype=String)
```

### Excel Files (.xlsx, .xls)
```julia
using XLSX, DataFrames
# Read first sheet
xf = XLSX.readxlsx("file.xlsx")
sheet_names = XLSX.sheetnames(xf)
df = DataFrame(XLSX.readtable("file.xlsx", sheet_names[1]))

# Read specific sheet
df = DataFrame(XLSX.readtable("file.xlsx", "Sheet1"))

# Handle missing values
df = DataFrame(XLSX.readtable("file.xlsx", "Sheet1"; infer_eltypes=true))
```

### Parquet Files (.parquet)
```julia
using Parquet, DataFrames
# Read existing parquet
df = DataFrame(read_parquet("file.parquet"))
# Alternative using Parquet.File
pf = Parquet.File("file.parquet")
df = DataFrame(pf)
```

### JSON Files (.json)
```julia
using JSON3, DataFrames
# Read JSON array of objects
json_str = read("file.json", String)
data = JSON3.read(json_str)
# Convert to DataFrame if structure allows
df = DataFrame(data)
```

### Generic File Type Detection and Handling
```julia
function detect_and_read_file(filepath::String)
    ext = lowercase(splitext(filepath)[2])
    
    if ext in [".csv", ".txt"]
        return CSV.read(filepath, DataFrame)
    elseif ext in [".xlsx", ".xls"]
        xf = XLSX.readxlsx(filepath)
        sheet = XLSX.sheetnames(xf)[1]
        return DataFrame(XLSX.readtable(filepath, sheet))
    elseif ext == ".parquet"
        return DataFrame(read_parquet(filepath))
    elseif ext == ".json"
        json_str = read(filepath, String)
        data = JSON3.read(json_str)
        return DataFrame(data)
    elseif ext == ".tsv"
        return CSV.read(filepath, DataFrame; delim='\t')
    else
        error("Unsupported file type: $ext")
    end
end
```

## Error Handling Patterns

### String Type Issues with Parquet
```julia
# Convert String15/String31 to String before writing Parquet
df_converted = mapcols(col -> eltype(col) <: AbstractString ? String.(col) : col, df)
write_parquet("output.parquet", df_converted)
```

### Missing Values Handling
```julia
# Replace missing with default values
for col in names(df)
    if eltype(df[!, col]) <: Union{Missing, Number}
        df[!, col] = coalesce.(df[!, col], 0)
    elseif eltype(df[!, col]) <: Union{Missing, AbstractString}
        df[!, col] = coalesce.(df[!, col], "")
    end
end
```

### Encoding Issues
```julia
# Force UTF-8 encoding for CSV
df = CSV.read("file.csv", DataFrame; stringtype=String, strict=false)
```

## Complete Ingestion Workflow Template

```julia
using CSV, DataFrames, Parquet, DuckDB, XLSX, JSON3, Statistics, Dates

function ingest_file(filepath::String, output_name::String="result")
    println("Starting ingestion of: ", filepath)
    
    # Step 1: Read file based on extension
    df = detect_and_read_file(filepath)
    println("Loaded data: ", size(df), " rows × columns")
    
    # Step 2: Convert string columns for Parquet compatibility
    df_converted = mapcols(col -> eltype(col) <: AbstractString ? String.(col) : col, df)
    
    # Step 3: Generate metadata
    metadata = Dict(
        "source_file" => filepath,
        "ingestion_time" => now(),
        "row_count" => nrow(df),
        "column_count" => ncol(df),
        "columns" => Dict()
    )
    
    for col in names(df)
        col_type = eltype(df[!, col])
        col_info = Dict(
            "type" => string(col_type),
            "null_count" => count(ismissing, df[!, col]),
            "unique_count" => length(unique(skipmissing(df[!, col])))
        )
        
        if col_type <: Union{Number, Union{Missing, Number}}
            non_missing = skipmissing(df[!, col])
            if !isempty(non_missing)
                col_info["min"] = minimum(non_missing)
                col_info["max"] = maximum(non_missing)
                col_info["mean"] = mean(non_missing)
                col_info["median"] = median(non_missing)
            end
        end
        
        metadata["columns"][string(col)] = col_info
    end
    
    # Step 4: Save as Parquet
    parquet_path = output_name * ".parquet"
    write_parquet(parquet_path, df_converted)
    println("Saved to: ", parquet_path)
    
    # Step 5: Store in DuckDB
    con = DBInterface.connect(DuckDB.DB)
    
    # Create data table
    DBInterface.execute(con, "CREATE TABLE data AS SELECT * FROM '" * parquet_path * "'")
    
    # Create metadata table
    DBInterface.execute(con, """
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    
    # Insert metadata
    for (k, v) in metadata
        if k != "columns"
            DBInterface.execute(con, "INSERT INTO metadata VALUES (?, ?)", 
                              [string(k), string(v)])
        end
    end
    
    # Store column metadata as JSON
    DBInterface.execute(con, "INSERT INTO metadata VALUES ('columns', ?)", 
                      [JSON3.write(metadata["columns"])])
    
    # Step 6: Run verification queries
    println("\n=== Verification Queries ===")
    
    # Total rows
    result = DBInterface.execute(con, "SELECT COUNT(*) as total FROM data")
    println("Total rows: ", DataFrame(result).total[1])
    
    # Sample data
    result = DBInterface.execute(con, "SELECT * FROM data LIMIT 3")
    println("\nSample data:")
    println(DataFrame(result))
    
    # Metadata check
    result = DBInterface.execute(con, "SELECT * FROM metadata")
    println("\nStored metadata:")
    println(DataFrame(result))
    
    DBInterface.close!(con)
    
    # Return summary
    return metadata
end
```

## Debug Information Collection

```julia
function ingest_with_debug(filepath::String)
    debug_info = Dict(
        "start_time" => now(),
        "file_path" => filepath,
        "file_size" => filesize(filepath),
        "steps" => []
    )
    
    try
        # Track each step
        push!(debug_info["steps"], ("read_start", now()))
        df = detect_and_read_file(filepath)
        push!(debug_info["steps"], ("read_complete", now(), size(df)))
        
        push!(debug_info["steps"], ("convert_start", now()))
        df_converted = mapcols(col -> eltype(col) <: AbstractString ? String.(col) : col, df)
        push!(debug_info["steps"], ("convert_complete", now()))
        
        push!(debug_info["steps"], ("parquet_write_start", now()))
        write_parquet("result.parquet", df_converted)
        push!(debug_info["steps"], ("parquet_write_complete", now()))
        
        debug_info["success"] = true
        debug_info["end_time"] = now()
        
    catch e
        debug_info["error"] = string(e)
        debug_info["error_type"] = typeof(e)
        debug_info["stacktrace"] = stacktrace()
        debug_info["success"] = false
        debug_info["end_time"] = now()
        rethrow(e)
    end
    
    return debug_info
end
```
