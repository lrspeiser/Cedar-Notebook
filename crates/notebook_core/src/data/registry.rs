use anyhow::{Result, Context};
use std::{path::{Path, PathBuf}, fs};

#[derive(Debug, Clone)]
pub struct DatasetRegistry {
    pub root: PathBuf,
}

impl DatasetRegistry {
    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }
    pub fn default_under_repo(repo_root: &Path) -> Self {
        Self { root: repo_root.join("data").join("parquet") }
    }
    pub fn register_parquet(&self, logical_name: &str, path: &Path) -> Result<PathBuf> {
        fs::create_dir_all(&self.root)?;
        let safe = logical_name.replace(|c: char| !(c.is_alphanumeric() || c=='_' || c=='-'), "_");
        let dst = self.root.join(format!("{}.parquet", safe));
        if path != dst {
            fs::copy(path, &dst).with_context(|| format!("copy {:?} -> {:?}", path, dst))?;
        }
        Ok(dst)
    }
}
