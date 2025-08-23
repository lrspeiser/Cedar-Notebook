#!/bin/bash
# Initialize and test DuckDB metadata database

echo "========================================="
echo "DuckDB Metadata Database Initialization"
echo "========================================="

# Ensure we're in the right directory
cd "$(dirname "$0")/.." || exit 1

echo "Working directory: $(pwd)"
echo ""

# Create runs directory if it doesn't exist
echo "Creating runs directory..."
mkdir -p runs

# Remove old metadata database to start fresh (optional)
if [ -f "runs/metadata.duckdb" ]; then
    echo "Found existing metadata.duckdb"
    echo -n "Remove and recreate? (y/n): "
    read -r response
    if [ "$response" = "y" ]; then
        rm -f runs/metadata.duckdb
        echo "Removed old database"
    fi
fi

# Create a simple Python script to test DuckDB initialization
cat > test_duckdb_init.py << 'EOF'
import duckdb
import os
from pathlib import Path

# Create runs directory
runs_dir = Path("runs")
runs_dir.mkdir(exist_ok=True)

# Connect to DuckDB (creates file if doesn't exist)
db_path = runs_dir / "metadata.duckdb"
print(f"Connecting to: {db_path}")

conn = duckdb.connect(str(db_path))

# Create tables
print("Creating tables...")

conn.execute("""
    CREATE TABLE IF NOT EXISTS datasets (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size BIGINT NOT NULL,
        file_type TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        row_count BIGINT,
        sample_data TEXT NOT NULL,
        uploaded_at TEXT NOT NULL
    )
""")

conn.execute("""
    CREATE TABLE IF NOT EXISTS dataset_columns (
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
        PRIMARY KEY (dataset_id, column_name),
        FOREIGN KEY (dataset_id) REFERENCES datasets(id)
    )
""")

# Create index
conn.execute("""
    CREATE INDEX IF NOT EXISTS idx_datasets_uploaded_at 
    ON datasets(uploaded_at DESC)
""")

# Verify tables exist
tables = conn.execute("SHOW TABLES").fetchall()
print(f"\nTables created: {tables}")

# Get table schemas
print("\nTable schemas:")
for table in ['datasets', 'dataset_columns']:
    schema = conn.execute(f"DESCRIBE {table}").fetchall()
    print(f"\n{table}:")
    for col in schema:
        print(f"  {col}")

# Test insert
print("\nTesting insert...")
conn.execute("""
    INSERT OR REPLACE INTO datasets 
    (id, file_path, file_name, file_size, file_type, title, description, row_count, sample_data, uploaded_at)
    VALUES ('test-001', '/tmp/test.csv', 'test.csv', 1024, 'CSV', 'Test Dataset', 'A test dataset', 100, 'col1,col2\n1,2\n3,4', '2024-01-01T00:00:00Z')
""")

# Verify insert
count = conn.execute("SELECT COUNT(*) FROM datasets").fetchone()[0]
print(f"Datasets in database: {count}")

# Clean up test data
conn.execute("DELETE FROM datasets WHERE id = 'test-001'")
print("Test data cleaned up")

conn.close()
print(f"\n✅ DuckDB metadata database initialized at: {db_path}")
print(f"   File size: {os.path.getsize(db_path)} bytes")
EOF

echo "Running DuckDB initialization test..."
python test_duckdb_init.py

# Check if file was created
echo ""
if [ -f "runs/metadata.duckdb" ]; then
    echo "✅ Database file created successfully"
    ls -la runs/metadata.duckdb
else
    echo "❌ Database file not created"
fi

# Clean up test script
rm -f test_duckdb_init.py

echo ""
echo "========================================="
echo "DuckDB initialization complete!"
echo "========================================="
