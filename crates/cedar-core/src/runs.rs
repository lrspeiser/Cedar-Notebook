use crate::util::{default_runs_root, new_run_dir};
use anyhow::Result;
use std::{path::PathBuf, fs};

#[derive(Debug, Clone)]
pub struct RunInfo {
    pub id: String,
    pub dir: PathBuf,
}

pub fn create_new_run(base: Option<&std::path::Path>) -> Result<RunInfo> {
    let dir = new_run_dir(base)?;
    let id = dir.file_name().unwrap().to_string_lossy().to_string();
    let debug_log = dir.join("debug.log");
    fs::write(debug_log, b"")?;
    Ok(RunInfo { id, dir })
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
