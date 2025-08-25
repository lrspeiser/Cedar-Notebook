// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

//! Cedar Notebook Server - Native Backend Only
//! 
//! This crate provides backend functionality for the Cedar desktop application.
//! NO WEB SERVER, NO BROWSER ACCESS, NATIVE DESKTOP ONLY.

mod file_index;

use anyhow::{Result, Context};
use notebook_core::{
    key_manager::KeyManager,
    duckdb_metadata::MetadataManager,
    data::registry::DatasetRegistry,
};
use crate::file_index::FileIndexer;
use std::path::Path;

pub use file_index::IndexedFile;

// Export types that the native app needs
pub use notebook_core::{
    key_manager::KeyManager as KeyManagerExport,
    duckdb_metadata::{MetadataManager as MetadataManagerExport, DatasetMetadata},
    data::registry::DatasetRegistry as DatasetRegistryExport,
};

/// Cedar backend service for native desktop app
pub struct CedarBackend {
    metadata_manager: Option<MetadataManager>,
    file_indexer: Option<FileIndexer>,
    data_registry: Option<DatasetRegistry>,
    key_manager: KeyManager,
}

impl CedarBackend {
    /// Create a new backend service
    pub fn new() -> Result<Self> {
        let project_dirs = directories::ProjectDirs::from("com", "CedarAI", "CedarAI")
            .context("Failed to get project directories")?;
        
        let data_dir = project_dirs.data_dir();
        std::fs::create_dir_all(data_dir)?;
        
        // Initialize components
        let db_path = data_dir.join("metadata.duckdb");
        let metadata_manager = MetadataManager::new(&db_path).ok();
        
        let index_path = data_dir.join("file_index.sqlite");
        let file_indexer = FileIndexer::new(&index_path).ok();
        
        // Dataset registry is optional for now
        let data_registry = None;
        
        let key_manager = KeyManager::new()?;
        
        Ok(Self {
            metadata_manager,
            file_indexer,
            data_registry,
            key_manager,
        })
    }
    
    /// Initialize API key from server
    pub async fn initialize_api_key(&self) -> Result<String> {
        self.key_manager.get_api_key().await
    }
    
    /// Submit a query to the agent
    pub async fn submit_query(&self, query: &str) -> Result<String> {
        use notebook_core::agent_loop::{agent_loop, AgentConfig, AgentResult};
        use std::path::PathBuf;
        
        // Get API key
        let api_key = self.key_manager.get_api_key().await?;
        
        // Create run directory
        let run_id = format!("run_{}", chrono::Utc::now().timestamp_millis());
        let runs_root = directories::ProjectDirs::from("com", "CedarAI", "CedarAI")
            .context("Failed to get project directories")?
            .data_dir()
            .join("runs");
        std::fs::create_dir_all(&runs_root)?;
        let run_dir = runs_root.join(&run_id);
        
        // Configure agent - NO relay for LLM calls, only direct OpenAI
        let config = AgentConfig {
            openai_api_key: api_key,
            openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".to_string()),
            openai_base: None,
            relay_url: None,  // Don't use relay for LLM calls - go direct to OpenAI
            app_shared_token: None,  // Not needed for direct OpenAI calls
        };
        
        // Run agent loop
        let result = agent_loop(&run_dir, query, 10, config).await?;
        
        // Return the final output
        Ok(result.final_output.unwrap_or_else(|| format!("Completed in {} turns", result.turns_used)))
    }
    
    /// Upload and process a file
    pub fn upload_file(&mut self, path: &Path) -> Result<String> {
        
        // Import to DuckDB if supported
        // TODO: Implement proper file import to DuckDB
        
        Ok("File registered".to_string())
    }
    
    /// List all datasets
    pub fn list_datasets(&self) -> Result<Vec<notebook_core::duckdb_metadata::DatasetMetadata>> {
        if let Some(ref mm) = self.metadata_manager {
            return mm.list_datasets();
        }
        Ok(Vec::new())
    }
    
    /// Get dataset details
    pub fn get_dataset(&self, dataset_id: &str) -> Result<Option<notebook_core::duckdb_metadata::DatasetMetadata>> {
        if let Some(ref mm) = self.metadata_manager {
            return mm.get_dataset(dataset_id);
        }
        Ok(None)
    }
    
    /// Delete a dataset
    pub fn delete_dataset(&self, dataset_id: &str) -> Result<()> {
        if let Some(ref mm) = self.metadata_manager {
            return mm.delete_dataset(dataset_id);
        }
        Ok(())
    }
    
    /// Search for files
    pub fn search_files(&self, query: &str, limit: usize) -> Result<Vec<crate::file_index::IndexedFile>> {
        if let Some(ref idx) = self.file_indexer {
            let mut results = idx.search_instant(query, limit)?;
            
            // Fall back to Spotlight if no results
            if results.is_empty() && !query.trim().is_empty() {
                results = idx.spotlight_search_fallback(query)?;
            }
            
            return Ok(results);
        }
        Ok(Vec::new())
    }
    
    /// Rebuild file index
    pub fn rebuild_file_index(&mut self) -> Result<usize> {
        if let Some(ref mut idx) = self.file_indexer {
            return idx.seed_from_spotlight(None);
        }
        Ok(0)
    }
    
    /// Get file index statistics
    pub fn get_index_stats(&self) -> Result<serde_json::Value> {
        if let Some(ref idx) = self.file_indexer {
            return idx.get_stats();
        }
        Ok(serde_json::json!({
            "total_files": 0,
            "indexed_at": null
        }))
    }
}

/// Initialize the Cedar backend for native desktop use
pub fn initialize_native() -> anyhow::Result<CedarBackend> {
    CedarBackend::new()
}

// No web server, no HTTP endpoints, no browser opening
// This is a pure backend library for the native desktop app
