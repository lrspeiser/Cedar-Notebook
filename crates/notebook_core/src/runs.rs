use crate::util::{default_runs_root, new_run_dir};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, fs};

#[derive(Debug, Clone)]
pub struct RunInfo {
    pub id: String,
    pub dir: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Manifest {
    pub artifacts: Vec<ManifestEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestEntry {
    pub r#type: String,      // e.g., "vega_lite", "plotly", "image", "table_parquet"
    pub path: String,        // relative path under run dir
    pub mime: String,        // e.g., "application/vnd.vegalite+json", "image/png", "application/parquet"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spec_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extra: Option<serde_json::Value>,
}

pub fn create_new_run(base: Option<&std::path::Path>) -> Result<RunInfo> {
    let dir = new_run_dir(base)?;
    let id = dir.file_name().unwrap().to_string_lossy().to_string();
    let debug_log = dir.join("debug.log");
    fs::write(debug_log, b"")?;
    // Initialize empty manifest
    let manifest_path = dir.join("manifest.json");
    let empty = Manifest::default();
    fs::write(&manifest_path, serde_json::to_vec_pretty(&empty)?)?;
    Ok(RunInfo { id, dir })
}

pub fn append_manifest(run_dir: &std::path::Path, entry: ManifestEntry) -> Result<()> {
    let path = run_dir.join("manifest.json");
    let mut manifest: Manifest = if path.exists() {
        let bytes = fs::read(&path)?;
        serde_json::from_slice(&bytes).unwrap_or_default()
    } else {
        Manifest::default()
    };
    manifest.artifacts.push(entry);
    fs::write(&path, serde_json::to_vec_pretty(&manifest)?)?;
    Ok(())
}

pub fn list_runs(limit: usize) -> Result<Vec<RunInfo>> {
    let root = default_runs_root()?;
    let mut runs = vec![];
    for entry in fs::read_dir(&root)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            runs.push(RunInfo{ id: entry.file_name().to_string_lossy().to_string(), dir: entry.path() });
        }
    }
    runs.sort_by(|a,b| b.id.cmp(&a.id));
    if runs.len() > limit { runs.truncate(limit); }
    Ok(runs)
}
