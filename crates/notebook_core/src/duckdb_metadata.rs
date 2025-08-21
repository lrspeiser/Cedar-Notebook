use anyhow::{Context, Result};
use duckdb::{Connection, params};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use chrono::{DateTime, Utc};

/// Metadata for a dataset stored in the system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatasetMetadata {
    pub id: String,
    pub file_path: String,
    pub file_name: String,
    pub file_size: u64,
    pub file_type: String,
    pub title: String,
    pub description: String,
    pub row_count: Option<i64>,
    pub column_info: Vec<ColumnInfo>,
    pub sample_data: String,  // First 30 lines
    pub uploaded_at: DateTime<Utc>,
}

/// Information about a column in a dataset
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColumnInfo {
    pub name: String,
    pub data_type: String,
    pub description: Option<String>,
    pub min_value: Option<serde_json::Value>,
    pub max_value: Option<serde_json::Value>,
    pub avg_value: Option<f64>,
    pub median_value: Option<f64>,
    pub null_count: Option<i64>,
    pub distinct_count: Option<i64>,
}

/// Statistics computed from a data file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileStatistics {
    pub row_count: i64,
    pub columns: Vec<ColumnStats>,
    pub sample_rows: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColumnStats {
    pub name: String,
    pub data_type: String,
    pub min: Option<serde_json::Value>,
    pub max: Option<serde_json::Value>,
    pub avg: Option<f64>,
    pub median: Option<f64>,
    pub null_count: i64,
    pub distinct_count: i64,
}

/// Manager for DuckDB metadata operations
pub struct MetadataManager {
    db_path: PathBuf,
}

impl MetadataManager {
    /// Create a new metadata manager with the given database path
    pub fn new(db_path: impl AsRef<Path>) -> Result<Self> {
        let db_path = db_path.as_ref().to_path_buf();
        
        // Ensure parent directory exists
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let manager = Self { db_path };
        manager.initialize_db()?;
        Ok(manager)
    }
    
    /// Initialize the database schema
    fn initialize_db(&self) -> Result<()> {
        let conn = self.get_connection()?;
        
        // Create datasets table
        conn.execute(
            "CREATE TABLE IF NOT EXISTS datasets (
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
            )",
            [],
        )?;
        
        // Create columns table
        conn.execute(
            "CREATE TABLE IF NOT EXISTS dataset_columns (
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
                FOREIGN KEY (dataset_id) REFERENCES datasets(id) ON DELETE CASCADE
            )",
            [],
        )?;
        
        // Create index for faster lookups
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_datasets_uploaded_at ON datasets(uploaded_at DESC)",
            [],
        )?;
        
        Ok(())
    }
    
    /// Get a connection to the database
    fn get_connection(&self) -> Result<Connection> {
        Connection::open(&self.db_path)
            .context("Failed to open DuckDB connection")
    }
    
    /// Store dataset metadata in the database
    pub fn store_dataset(&self, metadata: &DatasetMetadata) -> Result<()> {
        let conn = self.get_connection()?;
        
        // Start transaction
        conn.execute("BEGIN TRANSACTION", [])?;
        
        // Insert dataset
        conn.execute(
            "INSERT OR REPLACE INTO datasets 
            (id, file_path, file_name, file_size, file_type, title, description, row_count, sample_data, uploaded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                metadata.id,
                metadata.file_path,
                metadata.file_name,
                metadata.file_size,
                metadata.file_type,
                metadata.title,
                metadata.description,
                metadata.row_count,
                metadata.sample_data,
                metadata.uploaded_at.to_rfc3339(),
            ],
        )?;
        
        // Delete existing columns for this dataset
        conn.execute(
            "DELETE FROM dataset_columns WHERE dataset_id = ?",
            params![metadata.id],
        )?;
        
        // Insert column information
        for col in &metadata.column_info {
            conn.execute(
                "INSERT INTO dataset_columns 
                (dataset_id, column_name, data_type, description, min_value, max_value, avg_value, median_value, null_count, distinct_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params![
                    metadata.id,
                    col.name,
                    col.data_type,
                    col.description,
                    col.min_value.as_ref().map(|v| v.to_string()),
                    col.max_value.as_ref().map(|v| v.to_string()),
                    col.avg_value,
                    col.median_value,
                    col.null_count,
                    col.distinct_count,
                ],
            )?;
        }
        
        // Commit transaction
        conn.execute("COMMIT", [])?;
        
        Ok(())
    }
    
    /// List all datasets in the database
    pub fn list_datasets(&self) -> Result<Vec<DatasetMetadata>> {
        let conn = self.get_connection()?;
        
        let mut stmt = conn.prepare(
            "SELECT id, file_path, file_name, file_size, file_type, title, description, row_count, sample_data, uploaded_at
            FROM datasets
            ORDER BY uploaded_at DESC"
        )?;
        
        let datasets = stmt.query_map([], |row| {
            let id: String = row.get(0)?;
            let uploaded_at_str: String = row.get(9)?;
            
            Ok(DatasetMetadata {
                id: id.clone(),
                file_path: row.get(1)?,
                file_name: row.get(2)?,
                file_size: row.get(3)?,
                file_type: row.get(4)?,
                title: row.get(5)?,
                description: row.get(6)?,
                row_count: row.get(7)?,
                column_info: Vec::new(), // Will be populated separately
                sample_data: row.get(8)?,
                uploaded_at: DateTime::parse_from_rfc3339(&uploaded_at_str)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
        
        // Load column info for each dataset
        let mut result = Vec::new();
        for mut dataset in datasets {
            dataset.column_info = self.get_column_info(&dataset.id)?;
            result.push(dataset);
        }
        
        Ok(result)
    }
    
    /// Get column information for a specific dataset
    fn get_column_info(&self, dataset_id: &str) -> Result<Vec<ColumnInfo>> {
        let conn = self.get_connection()?;
        
        let mut stmt = conn.prepare(
            "SELECT column_name, data_type, description, min_value, max_value, avg_value, median_value, null_count, distinct_count
            FROM dataset_columns
            WHERE dataset_id = ?
            ORDER BY column_name"
        )?;
        
        let columns = stmt.query_map([dataset_id], |row| {
            Ok(ColumnInfo {
                name: row.get(0)?,
                data_type: row.get(1)?,
                description: row.get(2)?,
                min_value: row.get::<_, Option<String>>(3)?
                    .and_then(|s| serde_json::from_str(&s).ok()),
                max_value: row.get::<_, Option<String>>(4)?
                    .and_then(|s| serde_json::from_str(&s).ok()),
                avg_value: row.get(5)?,
                median_value: row.get(6)?,
                null_count: row.get(7)?,
                distinct_count: row.get(8)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
        
        Ok(columns)
    }
    
    /// Get a specific dataset by ID
    pub fn get_dataset(&self, id: &str) -> Result<Option<DatasetMetadata>> {
        let conn = self.get_connection()?;
        
        let mut stmt = conn.prepare(
            "SELECT id, file_path, file_name, file_size, file_type, title, description, row_count, sample_data, uploaded_at
            FROM datasets
            WHERE id = ?"
        )?;
        
        let mut rows = stmt.query_map([id], |row| {
            let uploaded_at_str: String = row.get(9)?;
            
            Ok(DatasetMetadata {
                id: row.get(0)?,
                file_path: row.get(1)?,
                file_name: row.get(2)?,
                file_size: row.get(3)?,
                file_type: row.get(4)?,
                title: row.get(5)?,
                description: row.get(6)?,
                row_count: row.get(7)?,
                column_info: Vec::new(),
                sample_data: row.get(8)?,
                uploaded_at: DateTime::parse_from_rfc3339(&uploaded_at_str)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
            })
        })?;
        
        if let Some(row_result) = rows.next() {
            let mut dataset = row_result?;
            dataset.column_info = self.get_column_info(&dataset.id)?;
            Ok(Some(dataset))
        } else {
            Ok(None)
        }
    }
    
    /// Delete a dataset from the database
    pub fn delete_dataset(&self, id: &str) -> Result<()> {
        let conn = self.get_connection()?;
        conn.execute("DELETE FROM datasets WHERE id = ?", params![id])?;
        Ok(())
    }
    
    /// Create a table in DuckDB from a CSV file
    pub fn create_table_from_csv(&self, file_path: &Path, table_name: &str) -> Result<FileStatistics> {
        let conn = self.get_connection()?;
        
        // Read CSV into a table
        let query = format!(
            "CREATE OR REPLACE TABLE {} AS SELECT * FROM read_csv_auto('{}', header=true)",
            table_name,
            file_path.display()
        );
        conn.execute(&query, [])?;
        
        // Get row count
        let row_count: i64 = conn.query_row(
            &format!("SELECT COUNT(*) FROM {}", table_name),
            [],
            |row| row.get(0)
        )?;
        
        // Get column information and statistics
        let columns = self.analyze_table(&conn, table_name)?;
        
        // Get sample rows (first 30)
        let sample_rows = self.get_sample_rows(&conn, table_name, 30)?;
        
        Ok(FileStatistics {
            row_count,
            columns,
            sample_rows,
        })
    }
    
    /// Analyze a table to get column statistics
    fn analyze_table(&self, conn: &Connection, table_name: &str) -> Result<Vec<ColumnStats>> {
        // Get column names and types
        let mut stmt = conn.prepare(&format!(
            "SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = '{}'",
            table_name
        ))?;
        
        let column_info: Vec<(String, String)> = stmt.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;
        
        let mut columns = Vec::new();
        
        for (col_name, data_type) in column_info {
            let mut stats = ColumnStats {
                name: col_name.clone(),
                data_type: data_type.clone(),
                min: None,
                max: None,
                avg: None,
                median: None,
                null_count: 0,
                distinct_count: 0,
            };
            
            // Get null count
            stats.null_count = conn.query_row(
                &format!("SELECT COUNT(*) FROM {} WHERE {} IS NULL", table_name, col_name),
                [],
                |row| row.get(0)
            )?;
            
            // Get distinct count
            stats.distinct_count = conn.query_row(
                &format!("SELECT COUNT(DISTINCT {}) FROM {}", col_name, table_name),
                [],
                |row| row.get(0)
            )?;
            
            // For numeric types, get min, max, avg, median
            if data_type.contains("INT") || data_type.contains("FLOAT") || data_type.contains("DOUBLE") || data_type.contains("DECIMAL") {
                // Min
                let min_val: Option<f64> = conn.query_row(
                    &format!("SELECT MIN({}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
                stats.min = min_val.map(|v| serde_json::Value::from(v));
                
                // Max
                let max_val: Option<f64> = conn.query_row(
                    &format!("SELECT MAX({}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
                stats.max = max_val.map(|v| serde_json::Value::from(v));
                
                // Average
                stats.avg = conn.query_row(
                    &format!("SELECT AVG({}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
                
                // Median (using PERCENTILE_CONT)
                stats.median = conn.query_row(
                    &format!("SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY {}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
            } else if data_type.contains("VARCHAR") || data_type.contains("TEXT") {
                // For string types, get min and max (lexicographically)
                let min_val: Option<String> = conn.query_row(
                    &format!("SELECT MIN({}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
                stats.min = min_val.map(|v| serde_json::Value::String(v));
                
                let max_val: Option<String> = conn.query_row(
                    &format!("SELECT MAX({}) FROM {}", col_name, table_name),
                    [],
                    |row| row.get(0)
                ).ok();
                stats.max = max_val.map(|v| serde_json::Value::String(v));
            }
            
            columns.push(stats);
        }
        
        Ok(columns)
    }
    
    /// Get sample rows from a table
    fn get_sample_rows(&self, conn: &Connection, table_name: &str, limit: usize) -> Result<Vec<serde_json::Value>> {
        let query = format!("SELECT * FROM {} LIMIT {}", table_name, limit);
        let mut stmt = conn.prepare(&query)?;
        
        // Get column count
        let column_count = stmt.column_count();
        
        let rows = stmt.query_map([], |row| {
            let mut obj = serde_json::Map::new();
            
            for i in 0..column_count {
                let col_name = row.as_ref().column_name(i)?.to_string();
                
                // Try to get value as different types
                if let Ok(val) = row.get::<_, i64>(i) {
                    obj.insert(col_name, serde_json::Value::from(val));
                } else if let Ok(val) = row.get::<_, f64>(i) {
                    obj.insert(col_name, serde_json::Value::from(val));
                } else if let Ok(val) = row.get::<_, String>(i) {
                    obj.insert(col_name, serde_json::Value::String(val));
                } else if let Ok(val) = row.get::<_, bool>(i) {
                    obj.insert(col_name, serde_json::Value::Bool(val));
                } else {
                    obj.insert(col_name, serde_json::Value::Null);
                }
            }
            
            Ok(serde_json::Value::Object(obj))
        })?
        .collect::<Result<Vec<_>, _>>()?;
        
        Ok(rows)
    }
}

/// Extract the first N lines from a file as a string
pub fn extract_sample_lines(file_path: &Path, max_lines: usize) -> Result<String> {
    use std::io::{BufRead, BufReader};
    use std::fs::File;
    
    let file = File::open(file_path)?;
    let reader = BufReader::new(file);
    
    let mut lines = Vec::new();
    for (i, line) in reader.lines().enumerate() {
        if i >= max_lines {
            break;
        }
        lines.push(line?);
    }
    
    Ok(lines.join("\n"))
}

/// Detect the file type based on extension and content
pub fn detect_file_type(file_path: &Path) -> String {
    let extension = file_path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("");
    
    match extension.to_lowercase().as_str() {
        "csv" => "CSV".to_string(),
        "tsv" => "TSV".to_string(),
        "json" => "JSON".to_string(),
        "jsonl" => "JSONL".to_string(),
        "parquet" => "Parquet".to_string(),
        "xlsx" | "xls" => "Excel".to_string(),
        _ => "Unknown".to_string(),
    }
}
