use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

#[derive(Debug, Deserialize)]
pub struct SearchFilesRequest {
    pub filename: String,
    pub search_paths: Option<Vec<String>>,
    pub max_results: Option<usize>,
}

#[derive(Debug, Serialize)]
pub struct FileMatch {
    pub path: String,
    pub directory: String,
    pub filename: String,
    pub size: u64,
    pub modified: String,
}

/// Search for files matching the given filename pattern
pub fn search_files(request: SearchFilesRequest) -> anyhow::Result<Vec<FileMatch>> {
    let mut matches = Vec::new();
    let max_results = request.max_results.unwrap_or(20);
    
    // Default search paths if none provided
    let search_paths = if let Some(paths) = request.search_paths {
        paths
    } else {
        // Common locations where data files might be
        vec![
            dirs::home_dir().unwrap_or_default().to_string_lossy().to_string(),
            dirs::download_dir().unwrap_or_default().to_string_lossy().to_string(),
            dirs::desktop_dir().unwrap_or_default().to_string_lossy().to_string(),
            dirs::document_dir().unwrap_or_default().to_string_lossy().to_string(),
            "/tmp".to_string(),
        ]
    };
    
    // Search each path
    for search_path in search_paths {
        if matches.len() >= max_results {
            break;
        }
        
        let path = PathBuf::from(&search_path);
        if !path.exists() {
            continue;
        }
        
        // Walk the directory tree (limit depth to avoid searching too deep)
        for entry in WalkDir::new(&path)
            .max_depth(3)  // Don't go too deep
            .follow_links(false)  // Don't follow symlinks
            .into_iter()
            .filter_map(|e| e.ok())
        {
            if matches.len() >= max_results {
                break;
            }
            
            let entry_path = entry.path();
            if entry_path.is_file() {
                if let Some(filename) = entry_path.file_name() {
                    let filename_str = filename.to_string_lossy();
                    
                    // Case-insensitive match
                    if filename_str.to_lowercase().contains(&request.filename.to_lowercase()) {
                        // Get file metadata
                        if let Ok(metadata) = entry_path.metadata() {
                            let parent = entry_path.parent()
                                .map(|p| p.to_string_lossy().to_string())
                                .unwrap_or_default();
                            
                            let modified = metadata.modified()
                                .ok()
                                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                .map(|d| {
                                    let datetime = chrono::DateTime::<chrono::Utc>::from_timestamp(
                                        d.as_secs() as i64, 0
                                    ).unwrap_or_default();
                                    datetime.format("%Y-%m-%d %H:%M:%S").to_string()
                                })
                                .unwrap_or_else(|| "Unknown".to_string());
                            
                            matches.push(FileMatch {
                                path: entry_path.to_string_lossy().to_string(),
                                directory: parent,
                                filename: filename_str.to_string(),
                                size: metadata.len(),
                                modified,
                            });
                        }
                    }
                }
            }
        }
    }
    
    // Sort by modified date (newest first)
    matches.sort_by(|a, b| b.modified.cmp(&a.modified));
    
    Ok(matches)
}
