# DuckDB Integration in Cedar

## Overview

Cedar includes full DuckDB support for data analysis, both through the Rust backend and Julia frontend. This enables powerful SQL-based data processing and seamless integration with uploaded datasets.

## Components

### 1. **Rust Backend (DuckDB-rs)**
The Cedar backend uses DuckDB through the `duckdb` Rust crate to:
- Store dataset metadata
- Compute statistics on uploaded files
- Manage the data catalog
- Execute SQL queries

### 2. **Julia Frontend (DuckDB.jl)**
The bundled Julia environment includes DuckDB.jl, allowing the agent to:
- Query uploaded CSV/JSON files directly
- Perform complex SQL operations in Julia code
- Join multiple datasets
- Export results to various formats

## Package Management

### Bundled Julia Packages
The Cedar app bundle includes these pre-installed Julia packages:
- **DuckDB.jl** - SQL database engine
- **CSV.jl** - CSV file reading/writing
- **DataFrames.jl** - Tabular data manipulation
- **JSON.jl / JSON3.jl** - JSON parsing
- **Parquet.jl** - Parquet file support
- **Plots.jl** - Data visualization
- **HTTP.jl** - Web requests

### Installation Process
When building the Cedar DMG:
1. `scripts/embed-julia.sh` downloads and embeds Julia
2. All required packages are pre-installed in `julia_env/depot`
3. The bundle includes a complete, self-contained Julia environment
4. No internet connection needed at runtime for package installation

## Data Flow

### Upload Process
1. User uploads CSV/JSON file through web UI
2. Backend analyzes file with DuckDB:
   - Creates temporary table
   - Computes column statistics
   - Extracts sample data
3. LLM generates user-friendly metadata
4. Metadata stored in `metadata.duckdb`

### Query Process
1. User asks question about data
2. Agent receives list of available datasets
3. Agent generates Julia code using DuckDB.jl:
   ```julia
   using DuckDB
   db = DuckDB.DB()
   
   # Query uploaded CSV directly
   result = DuckDB.query(db, """
       SELECT * FROM read_csv_auto('/path/to/uploaded.csv')
       WHERE column > 100
       LIMIT 10
   """)
   ```
4. Results returned to user

## File Locations

### In Development
```
.cedar/
  julia_env/
    Project.toml          # Local Julia environment
    depot/                # Package cache
  runs/
    metadata.duckdb       # Dataset metadata database
```

### In App Bundle
```
Cedar.app/Contents/Resources/
  julia/                  # Embedded Julia runtime
  julia_env/              
    Project.toml          # Bundled packages
    depot/                # Pre-compiled packages
  julia-wrapper.sh        # Environment setup script
```

## Database Schema

### Datasets Table
```sql
CREATE TABLE datasets (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size BIGINT NOT NULL,
    file_type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    row_count BIGINT,
    sample_data TEXT NOT NULL,
    uploaded_at TIMESTAMP NOT NULL
)
```

### Dataset Columns Table
```sql
CREATE TABLE dataset_columns (
    dataset_id TEXT NOT NULL,
    column_name TEXT NOT NULL,
    data_type TEXT NOT NULL,
    description TEXT,
    min_value TEXT,
    max_value TEXT,
    avg_value DOUBLE,
    median_value DOUBLE,
    null_count BIGINT,
    distinct_count BIGINT,
    PRIMARY KEY (dataset_id, column_name)
)
```

## Example Usage

### Upload Data
```javascript
// Web UI - Upload CSV file
const formData = new FormData();
formData.append('files', csvFile);
await fetch('/datasets/upload', {
    method: 'POST',
    body: formData
});
```

### Query Data in Julia
```julia
using DuckDB, DataFrames

# Connect to DuckDB
db = DuckDB.DB()

# Query uploaded sales data
sales_df = DataFrame(DuckDB.query(db, """
    SELECT 
        product_category,
        SUM(revenue) as total_revenue,
        AVG(quantity) as avg_quantity
    FROM read_csv_auto('/tmp/sales_data.csv')
    GROUP BY product_category
    ORDER BY total_revenue DESC
"""))

println(sales_df)
```

### List Available Datasets
```bash
# API endpoint
curl http://localhost:8080/datasets

# Returns:
{
  "datasets": [
    {
      "id": "abc-123",
      "title": "Q3 Sales Report",
      "description": "Quarterly sales data with product categories",
      "row_count": 5000,
      "column_count": 12
    }
  ]
}
```

## Troubleshooting

### Package Installation Issues
If Julia packages are missing:
```bash
# Re-run embedding script
./scripts/embed-julia.sh

# Or manually install in Julia
julia --project=apps/cedar-bundle/resources/julia_env
julia> using Pkg
julia> Pkg.add("DuckDB")
julia> Pkg.precompile()
```

### Database Connection Errors
Check database exists:
```bash
ls -la ~/.cedar/runs/metadata.duckdb
```

Reset database if corrupted:
```bash
rm ~/.cedar/runs/metadata.duckdb
# Restart Cedar - database will be recreated
```

## Performance Considerations

- DuckDB can handle datasets up to available RAM
- CSV files are read on-demand, not loaded into memory
- Statistics are computed once during upload
- Metadata queries are indexed for fast lookups
- Julia precompilation improves startup time

## Security Notes

- Uploaded files stored in temp directory
- SQL injection prevented through parameterized queries
- File paths validated to prevent directory traversal
- LLM prompts sanitized before processing
