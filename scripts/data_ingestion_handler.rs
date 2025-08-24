// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use std::path::Path;
use std::process::Command;
use serde_json::json;

// This module handles the complete data ingestion workflow
// 1. Preview data files (first 30 rows)
// 2. Pass preview + metadata to LLM
// 3. LLM generates Julia code
// 4. Execute Julia code and capture results
// 5. Handle errors by passing back to LLM for self-correction

pub struct DataIngestionHandler {
    debug_mode: bool,
    max_retries: usize,
}

impl DataIngestionHandler {
    pub fn new() -> Self {
        Self {
            debug_mode: true,
            max_retries: 3,
        }
    }

    /// Try to preview a data file using available methods
    pub fn preview_data_file(&self, filepath: &Path) -> Result<String, String> {
        let extension = filepath.extension()
            .and_then(|s| s.to_str())
            .unwrap_or("");

        // Log the attempt
        if self.debug_mode {
            eprintln!("[DEBUG] Attempting to preview file: {:?} (type: {})", filepath, extension);
        }

        match extension.to_lowercase().as_str() {
            "csv" => self.preview_csv_rust(filepath)
                .or_else(|_| self.preview_with_julia(filepath, "CSV")),
            "parquet" => self.preview_parquet_rust(filepath)
                .or_else(|_| self.preview_with_julia(filepath, "Parquet")),
            "xlsx" | "xls" => self.preview_with_julia(filepath, "XLSX"),
            "json" => self.preview_json_rust(filepath)
                .or_else(|_| self.preview_with_julia(filepath, "JSON")),
            _ => Err(format!("Unknown file type: {}", extension))
        }
    }

    /// Try to preview CSV using Rust
    fn preview_csv_rust(&self, filepath: &Path) -> Result<String, String> {
        if self.debug_mode {
            eprintln!("[DEBUG] Trying Rust CSV reader for: {:?}", filepath);
        }

        // Use csv crate if available
        let mut reader = csv::Reader::from_path(filepath)
            .map_err(|e| format!("CSV read error: {}", e))?;
        
        let mut preview = String::new();
        let headers = reader.headers()
            .map_err(|e| format!("Header read error: {}", e))?;
        
        preview.push_str(&format!("Headers: {:?}\n", headers));
        preview.push_str("First 30 rows:\n");
        
        for (i, result) in reader.records().enumerate() {
            if i >= 30 { break; }
            let record = result.map_err(|e| format!("Record read error: {}", e))?;
            preview.push_str(&format!("Row {}: {:?}\n", i + 1, record));
        }
        
        Ok(preview)
    }

    /// Try to preview Parquet using Rust
    fn preview_parquet_rust(&self, filepath: &Path) -> Result<String, String> {
        // This would use arrow/parquet crate if available
        Err("Parquet preview not implemented in Rust".to_string())
    }

    /// Try to preview JSON using Rust
    fn preview_json_rust(&self, filepath: &Path) -> Result<String, String> {
        use std::fs::File;
        let content = fs::read_to_string(filepath)
            .map_err(|e| format!("File read error: {}", e))?;
        
        let value: serde_json::Value = serde_json::from_str(&content)
            .map_err(|e| format!("JSON parse error: {}", e))?;
        
        // Pretty print first part of JSON
        let preview = serde_json::to_string_pretty(&value)
            .map_err(|e| format!("JSON format error: {}", e))?;
        
        // Limit to first 3000 chars for preview
        Ok(preview.chars().take(3000).collect())
    }

    /// Fallback: Use Julia to preview any file type
    fn preview_with_julia(&self, filepath: &Path, file_type: &str) -> Result<String, String> {
        if self.debug_mode {
            eprintln!("[DEBUG] Falling back to Julia preview for {} file: {:?}", file_type, filepath);
        }

        let julia_code = match file_type {
            "CSV" => format!(r#"
                using CSV, DataFrames
                df = CSV.read("{}", DataFrame; limit=30)
                println("Shape: ", size(df))
                println("Columns: ", names(df))
                println("\nFirst 30 rows:")
                show(df, allrows=true, allcols=true)
            "#, filepath.display()),
            
            "Parquet" => format!(r#"
                using Parquet, DataFrames
                pf = Parquet.File("{}")
                df = DataFrame(pf; limit=30)
                println("Shape: ", size(df))
                println("Columns: ", names(df))
                println("\nFirst 30 rows:")
                show(df, allrows=true, allcols=true)
            "#, filepath.display()),
            
            "XLSX" => format!(r#"
                using XLSX, DataFrames
                xf = XLSX.readxlsx("{}")
                sheet_names = XLSX.sheetnames(xf)
                println("Sheets found: ", sheet_names)
                
                # Read first sheet
                first_sheet = sheet_names[1]
                data = XLSX.readtable("{}", first_sheet; infer_eltypes=true)
                df = DataFrame(data)
                
                # Limit to first 30 rows
                df_preview = first(df, min(30, nrow(df)))
                println("\nShape: ", size(df_preview))
                println("Columns: ", names(df_preview))
                println("\nFirst 30 rows from sheet '", first_sheet, "':")
                show(df_preview, allrows=true, allcols=true)
            "#, filepath.display(), filepath.display()),
            
            _ => return Err(format!("Julia preview not implemented for {}", file_type))
        };

        let output = Command::new("julia")
            .arg("-e")
            .arg(&julia_code)
            .output()
            .map_err(|e| format!("Julia execution error: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    /// Main ingestion workflow with LLM interaction
    pub async fn ingest_file_with_llm(
        &self,
        filepath: &Path,
        llm_client: &LLMClient,
        db_path: &Path,
    ) -> Result<IngestionResult, String> {
        let mut attempt = 0;
        let mut all_debug_info = Vec::new();
        
        // Step 1: Get file preview
        let preview = self.preview_data_file(filepath)?;
        
        // Store preview debug info
        all_debug_info.push(json!({
            "step": "preview",
            "filepath": filepath.display().to_string(),
            "preview_length": preview.len(),
            "preview_method": if preview.contains("[DEBUG]") { "julia" } else { "rust" },
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }));

        // Step 2: Get file metadata
        let metadata = std::fs::metadata(filepath)
            .map_err(|e| format!("Cannot read file metadata: {}", e))?;
        
        let file_info = json!({
            "path": filepath.display().to_string(),
            "size_bytes": metadata.len(),
            "extension": filepath.extension().and_then(|s| s.to_str()).unwrap_or(""),
            "preview": preview,
            "available_packages": self.get_julia_packages()?,
        });

        while attempt < self.max_retries {
            attempt += 1;
            
            // Step 3: Generate Julia code via LLM
            let prompt = if attempt == 1 {
                format!(
                    r#"Generate Julia code to:
1. Read the complete file at: {}
2. Convert it to a Parquet file at: {}.parquet
3. Store metadata in DuckDB at: {}
4. Run a test query to verify the data
5. Return summary statistics

File information:
{}

Available Julia packages:
{}

Requirements:
- Handle all potential errors gracefully
- Include detailed logging at each step
- Create the parquet file in the same directory
- Store metadata including: filename, row_count, column_count, column_names, data_types
- Run a test query like "SELECT COUNT(*) FROM data" or "SELECT * FROM data LIMIT 5"
- Return success confirmation with the test query results

Generate ONLY executable Julia code, no explanations."#,
                    filepath.display(),
                    filepath.with_extension("").display(),
                    db_path.display(),
                    serde_json::to_string_pretty(&file_info).unwrap(),
                    self.get_julia_packages().unwrap_or_else(|_| "CSV, DataFrames, Parquet, XLSX".to_string())
                )
            } else {
                // Retry with error context
                let last_error = &all_debug_info.last().unwrap()["error"];
                format!(
                    r#"The previous Julia code failed with this error:
{}

Please fix the code and try again. Here's the file information again:
{}

Generate corrected Julia code that handles this specific error."#,
                    last_error,
                    serde_json::to_string_pretty(&file_info).unwrap()
                )
            };

            // Log LLM prompt
            all_debug_info.push(json!({
                "step": "llm_prompt",
                "attempt": attempt,
                "prompt_length": prompt.len(),
                "timestamp": chrono::Utc::now().to_rfc3339(),
            }));

            // Get Julia code from LLM
            let julia_code = llm_client.generate_code(prompt).await
                .map_err(|e| format!("LLM generation error: {}", e))?;

            // Log generated code
            all_debug_info.push(json!({
                "step": "generated_code",
                "attempt": attempt,
                "code_length": julia_code.len(),
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "code": julia_code.clone(),
            }));

            // Step 4: Execute Julia code
            if self.debug_mode {
                eprintln!("[DEBUG] Executing Julia code (attempt {}/{})", attempt, self.max_retries);
                eprintln!("[DEBUG] Code:\n{}", julia_code);
            }

            let output = Command::new("julia")
                .arg("-e")
                .arg(&julia_code)
                .output()
                .map_err(|e| format!("Julia execution error: {}", e))?;

            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();

            // Log execution result
            all_debug_info.push(json!({
                "step": "execution",
                "attempt": attempt,
                "success": output.status.success(),
                "exit_code": output.status.code(),
                "stdout_length": stdout.len(),
                "stderr_length": stderr.len(),
                "stdout": stdout.clone(),
                "stderr": stderr.clone(),
                "timestamp": chrono::Utc::now().to_rfc3339(),
            }));

            if output.status.success() {
                // Success! Store final result
                let result = IngestionResult {
                    success: true,
                    source_file: filepath.display().to_string(),
                    parquet_file: filepath.with_extension("parquet").display().to_string(),
                    rows_processed: self.extract_row_count(&stdout).unwrap_or(0),
                    test_query_result: stdout.clone(),
                    debug_info: all_debug_info,
                    attempts_needed: attempt,
                };

                // Store in database
                self.store_metadata_in_db(db_path, &result)?;

                if self.debug_mode {
                    eprintln!("[DEBUG] Success! File ingested after {} attempt(s)", attempt);
                    eprintln!("[DEBUG] Parquet file created: {}", result.parquet_file);
                }

                return Ok(result);
            } else {
                // Store error for retry
                all_debug_info.push(json!({
                    "step": "error",
                    "attempt": attempt,
                    "error": stderr,
                    "timestamp": chrono::Utc::now().to_rfc3339(),
                }));

                if self.debug_mode {
                    eprintln!("[DEBUG] Attempt {} failed: {}", attempt, stderr);
                }
            }
        }

        Err(format!("Failed after {} attempts. Debug info stored.", self.max_retries))
    }

    /// Get list of installed Julia packages
    fn get_julia_packages(&self) -> Result<String, String> {
        let output = Command::new("julia")
            .arg("-e")
            .arg("using Pkg; for (name, _) in Pkg.dependencies() println(name) end")
            .output()
            .map_err(|e| format!("Cannot list Julia packages: {}", e))?;

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Extract row count from Julia output
    fn extract_row_count(&self, output: &str) -> Option<usize> {
        // Look for patterns like "Shape: (100, 5)" or "rows: 100"
        if let Some(shape_match) = output.find("Shape: (") {
            let remaining = &output[shape_match + 8..];
            if let Some(comma_pos) = remaining.find(',') {
                return remaining[..comma_pos].parse().ok();
            }
        }
        None
    }

    /// Store metadata in DuckDB
    fn store_metadata_in_db(&self, db_path: &Path, result: &IngestionResult) -> Result<(), String> {
        // This would use DuckDB connection to store metadata
        // For now, we'll save as JSON
        let metadata_path = db_path.with_extension("metadata.json");
        std::fs::write(
            metadata_path,
            serde_json::to_string_pretty(result).unwrap()
        ).map_err(|e| format!("Cannot store metadata: {}", e))?;
        
        Ok(())
    }
}

#[derive(Debug, serde::Serialize)]
pub struct IngestionResult {
    pub success: bool,
    pub source_file: String,
    pub parquet_file: String,
    pub rows_processed: usize,
    pub test_query_result: String,
    pub debug_info: Vec<serde_json::Value>,
    pub attempts_needed: usize,
}

// Placeholder for LLM client
pub struct LLMClient;

impl LLMClient {
    pub async fn generate_code(&self, prompt: String) -> Result<String, String> {
        // This would call the actual LLM API
        // For now, return a placeholder
        Ok("# LLM generated code would go here".to_string())
    }
}
