use anyhow::{Context, Result};
use std::path::{Path, PathBuf};
use std::fs;
use notebook_core::{
    agent_loop::{agent_loop, AgentConfig},
    duckdb_metadata::{MetadataManager, DatasetMetadata},
    runs::create_new_run,
    util::default_runs_root,
};
use chrono::Utc;

/// Enhanced data ingestion that uses the agent to process CSV files
pub async fn ingest_with_agent(
    runs_root: &Path,
    file_path: PathBuf,
    openai_api_key: String,
) -> Result<()> {
    // Read file metadata
    let file_path = file_path.canonicalize()?;
    let file_name = file_path
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("Invalid file path"))?
        .to_string_lossy()
        .to_string();
    
    let file_size = fs::metadata(&file_path)?.len();
    let file_type = file_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("unknown")
        .to_string();
    
    // Read first 30 lines of the file
    let file_content = fs::read_to_string(&file_path)?;
    let sample_lines: Vec<&str> = file_content
        .lines()
        .take(30)
        .collect();
    let sample_data = sample_lines.join("\n");
    
    // Count total lines for context
    let total_lines = file_content.lines().count();
    
    // Create a comprehensive prompt for the agent
    let prompt = format!(
        r#"Process this data file and store it properly in our system.

FILE INFORMATION:
- Name: {}
- Size: {} bytes
- Type: {}
- Total rows: {}

FIRST 30 LINES OF DATA:
```
{}
```

REQUIREMENTS:
1. Load the CSV file from: {}
2. Convert it to Parquet format and save as "result.parquet"
3. Generate a user-friendly title and description for this dataset
4. Analyze each column and provide:
   - Column name and data type
   - Description of what the column represents
   - Min, max, average values (for numeric columns)
   - Distinct count and null count
5. Store the metadata using DuckDB
6. Use Julia with these packages: CSV, DataFrames, Parquet, DuckDB, Statistics
7. Output a PREVIEW_JSON block with the dataset summary

Please write Julia code that:
- Reads the CSV file
- Performs the analysis
- Saves to Parquet
- Computes all statistics
- Outputs the results in a structured format"#,
        file_name,
        file_size,
        file_type,
        total_lines,
        sample_data,
        file_path.display()
    );
    
    // Create a new run for this ingestion
    let run = create_new_run(Some(runs_root))?;
    
    // Configure the agent
    let cfg = AgentConfig {
        openai_api_key,
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".into()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url: None,
        app_shared_token: None,
    };
    
    // Run the agent to process the file
    println!("Processing {} with AI agent...", file_name);
    let result = agent_loop(&run.dir, &prompt, 30, cfg).await?;
    
    // Check if a parquet file was created
    let parquet_path = run.dir.join("result.parquet");
    if parquet_path.exists() {
        println!("✓ Successfully created Parquet file");
        
        // Store in DuckDB metadata if configured
        if let Ok(db_root) = default_runs_root() {
            let db_path = db_root.join("metadata.duckdb");
            let manager = MetadataManager::new(&db_path)?;
            
            // Try to extract metadata from the run output
            // This would be enhanced based on actual agent output
            // Generate a unique ID using timestamp and file name
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            let id = format!("{}_{}", file_name.replace('.', "_"), timestamp);
            
            let metadata = DatasetMetadata {
                id,
                file_path: file_path.to_string_lossy().to_string(),
                file_name: file_name.clone(),
                file_size,
                file_type,
                title: format!("Dataset: {}", file_name),
                description: format!("Processed from {} on {}", 
                    file_name, 
                    Utc::now().format("%Y-%m-%d")),
                row_count: Some(total_lines as i64 - 1), // Subtract header
                column_info: vec![], // Would be populated from agent output
                sample_data,
                uploaded_at: Utc::now(),
            };
            
            manager.store_dataset(&metadata)?;
            println!("✓ Stored metadata in DuckDB");
        }
        
        // Register in parquet registry
        if let Ok(cwd) = std::env::current_dir() {
            let reg = notebook_core::data::registry::DatasetRegistry::default_under_repo(&cwd);
            let dataset_name = file_name.replace('.', "_");
            let dst = reg.register_parquet(&dataset_name, &parquet_path)?;
            println!("✓ Registered dataset: {}", dst.display());
        }
    }
    
    if let Some(output) = result.final_output {
        println!("\nAgent Summary:\n{}", output);
    }
    
    Ok(())
}
