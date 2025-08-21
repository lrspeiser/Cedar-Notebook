use anyhow::Result;
use directories::ProjectDirs;
use std::{env, fs, path::{Path, PathBuf}};
use uuid::Uuid;

pub fn app_dirs() -> Result<ProjectDirs> {
    ProjectDirs::from("com", "CedarAI", "CedarAI").ok_or_else(|| anyhow::anyhow!("ProjectDirs unavailable"))
}

pub fn default_runs_root() -> Result<PathBuf> {
    // Check for environment variable override first
    if let Ok(custom_dir) = env::var("CEDAR_RUNS_DIR") {
        let root = PathBuf::from(custom_dir);
        fs::create_dir_all(&root)?;
        return Ok(root);
    }
    
    // Fall back to default location
    let pd = app_dirs()?;
    let root = pd.data_dir().join("runs");
    fs::create_dir_all(&root)?;
    Ok(root)
}

pub fn new_run_dir(base: Option<&Path>) -> Result<PathBuf> {
    let id = Uuid::new_v4().to_string();
    let root = match base {
        Some(b) => b.to_path_buf(),
        None => default_runs_root()?,
    };
    let dir = root.join(id);
    fs::create_dir_all(&dir)?;
    fs::create_dir_all(dir.join("cards"))?;
    Ok(dir)
}

pub fn write_string(path: &Path, s: &str) -> Result<()> {
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    fs::write(path, s)?;
    Ok(())
}

pub fn is_path_within(base: &Path, candidate: &Path) -> bool {
    match candidate.canonicalize().and_then(|p| base.canonicalize().map(|b| (b,p))) {
        Ok((b, p)) => p.starts_with(b),
        Err(_) => false,
    }
}

pub fn env_flag(name: &str) -> bool {
    env::var(name).map(|v| v == "1" || v.eq_ignore_ascii_case("true")).unwrap_or(false)
}
