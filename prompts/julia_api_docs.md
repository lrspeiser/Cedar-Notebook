# Julia Package API Documentation for Cedar

## Essential Packages and Usage

### 1. CSV Package
```julia
using CSV, DataFrames

# Reading CSV files
df = CSV.read("filename.csv", DataFrame)
df = CSV.read("filename.csv", DataFrame; delim=',', header=true)

# Writing CSV files
CSV.write("output.csv", df)
```

### 2. DataFrames Package
```julia
using DataFrames

# Creating DataFrames
df = DataFrame(name=["John", "Jane"], age=[30, 25], salary=[75000, 65000])

# Basic operations
nrow(df)                    # Number of rows
ncol(df)                    # Number of columns
names(df)                   # Column names
size(df)                    # (rows, cols)
describe(df)                # Statistical summary
first(df, 5)                # First 5 rows
last(df, 5)                 # Last 5 rows

# Selecting columns
df.column_name              # Access single column
df[:, :column_name]         # Alternative syntax
df[:, [:col1, :col2]]      # Multiple columns
select(df, :col1, :col2)    # Select specific columns

# Filtering
filter(row -> row.age > 25, df)
df[df.age .> 25, :]

# Grouping and aggregation
grouped = groupby(df, :city)
combine(grouped, :salary => mean => :avg_salary)

# Adding columns
df.new_col = df.col1 .+ df.col2
transform!(df, :salary => (x -> x .* 1.1) => :new_salary)
```

### 3. Parquet Package
```julia
using Parquet, DataFrames

# CORRECT API for writing Parquet files
write_parquet("output.parquet", df)

# Reading Parquet files
df = DataFrame(read_parquet("input.parquet"))

# Alternative using Parquet.File for reading
pf = Parquet.File("input.parquet")
df = DataFrame(pf)
```

### 4. DuckDB Package
```julia
using DuckDB, DataFrames

# Create connection
con = DBInterface.connect(DuckDB.DB, "database.duckdb")
# For in-memory database
con = DBInterface.connect(DuckDB.DB)

# Execute queries
result = DBInterface.execute(con, "SELECT * FROM table_name")
df = DataFrame(result)

# Create table from DataFrame
DuckDB.register_data_frame(con, df, "table_name")

# Run SQL on registered DataFrame
result = DBInterface.execute(con, "SELECT * FROM table_name WHERE age > 25")
df_result = DataFrame(result)

# Create permanent table
DBInterface.execute(con, "CREATE TABLE mytable AS SELECT * FROM table_name")

# Insert data
DBInterface.execute(con, "INSERT INTO mytable VALUES (?, ?, ?)", ["John", 30, 75000])

# Close connection
DBInterface.close!(con)
```

### 5. Statistics Package
```julia
using Statistics

# Basic statistics
mean(values)                # Mean
median(values)              # Median
std(values)                 # Standard deviation
var(values)                 # Variance
quantile(values, 0.25)      # First quartile
minimum(values)             # Minimum value
maximum(values)             # Maximum value

# For DataFrames columns
mean(df.column_name)
std(df.column_name)
```

### 6. JSON/JSON3 Packages
```julia
using JSON3

# Parse JSON string
data = JSON3.read("{\"name\":\"John\",\"age\":30}")

# Convert to JSON string
json_str = JSON3.write(df)

# Pretty printing
JSON3.pretty(data)

# Working with files
data = JSON3.read(read("file.json", String))
write("output.json", JSON3.write(df))
```

## Common Data Processing Patterns

### Complete CSV to Parquet Workflow
```julia
using CSV, DataFrames, Parquet, Statistics

# Read CSV
df = CSV.read("input.csv", DataFrame)

# Analyze data
println("Dataset shape: ", size(df))
println("Columns: ", names(df))
println("Summary statistics:")
println(describe(df))

# Process data
for col in names(df)
    if eltype(df[!, col]) <: Number
        println("$col - Mean: ", mean(skipmissing(df[!, col])))
        println("$col - Min: ", minimum(skipmissing(df[!, col])))
        println("$col - Max: ", maximum(skipmissing(df[!, col])))
    end
    println("$col - Unique values: ", length(unique(df[!, col])))
    println("$col - Missing values: ", sum(ismissing.(df[!, col])))
end

# Save to Parquet
write_parquet("output.parquet", df)
println("Data saved to output.parquet")
```

### DuckDB Integration Pattern
```julia
using DuckDB, DataFrames, Parquet

# Read Parquet into DuckDB
con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE TABLE data AS SELECT * FROM 'data.parquet'")

# Query the data
result = DBInterface.execute(con, "SELECT city, AVG(salary) as avg_salary FROM data GROUP BY city")
df_result = DataFrame(result)
println(df_result)

# Store metadata
DBInterface.execute(con, """
    CREATE TABLE metadata AS 
    SELECT 
        'data.parquet' as file_name,
        COUNT(*) as row_count,
        COUNT(DISTINCT city) as unique_cities
    FROM data
""")

DBInterface.close!(con)
```

### Output Formatting for Cedar
```julia
# For structured output that Cedar expects
function format_preview(df, max_rows=5)
    preview_data = Dict(
        "summary" => "Dataset with $(nrow(df)) rows and $(ncol(df)) columns",
        "columns" => [Dict("name" => String(col), "type" => string(eltype(df[!, col]))) for col in names(df)],
        "rows" => [Dict(String(k) => v for (k,v) in pairs(row)) for row in eachrow(first(df, max_rows))]
    )
    
    # Print as PREVIEW_JSON block
    println("```PREVIEW_JSON")
    println(JSON3.write(preview_data))
    println("```")
end
```

## Important Notes

1. **Always use println() for output** - This ensures the output is captured by the executor
2. **Use write_parquet() for Parquet files** - NOT Parquet.File() for writing
3. **Handle missing values** - Use skipmissing() when computing statistics
4. **Check column types** - Use eltype() before numeric operations
5. **Close database connections** - Always close DuckDB connections when done
6. **Output structure** - Use PREVIEW_JSON blocks for structured data output
