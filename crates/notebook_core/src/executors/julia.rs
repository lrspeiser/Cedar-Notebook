#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_run_julia_cell_simple() {
        let dir = tempdir().unwrap();
        let result = run_julia_cell(dir.path(), "println(\"hi from julia\")").unwrap();
        assert!(result.ok);
        assert_eq!(result.message.trim(), "hi from julia");
    }
}

use std::{
    fs,
    io::{BufRead, BufReader},
    path::Path,
    process::{Child, Command, Stdio},
    thread,
};
use tracing::{debug, info};

use crate::executors::ToolOutcome;


fn spawn_log_threads(child: &mut Child) -> (thread::JoinHandle<String>, thread::JoinHandle<String>) {
    let out_handle = {
        let stdout = child.stdout.take();
        thread::spawn(move || {
            let mut buf = String::new();
            if let Some(stdout) = stdout {
                let reader = BufReader::new(stdout);
                for line in reader.lines().flatten() {
                    let line = line.trim_end_matches(&['\r', '\n'][..]).to_string();
                    tracing::info!(target = "exec::stdout", "{line}");
                    buf.push_str(&line);
                    buf.push('\n');
                }
            }
            buf
        })
    };
    let err_handle = {
        let stderr = child.stderr.take();
        thread::spawn(move || {
            let mut buf = String::new();
            if let Some(stderr) = stderr {
                let reader = BufReader::new(stderr);
                for line in reader.lines().flatten() {
                    let line = line.trim_end_matches(&['\r', '\n'][..]).to_string();
                    tracing::warn!(target = "exec::stderr", "{line}");
                    buf.push_str(&line);
                    buf.push('\n');
                }
            }
            buf
        })
    };
    (out_handle, err_handle)
}

#[tracing::instrument(skip_all, fields(run_dir = %run_dir.display()))]
pub fn run_julia_cell(run_dir: &Path, code: &str) -> anyhow::Result<ToolOutcome> {
    // Write a temporary script; if you already do this differently, keep your path.
    let script_path = run_dir.join("cell.jl");
    fs::write(&script_path, code)?;
    debug!(script = %script_path.display(), "wrote Julia cell");

    // Check for embedded Julia first (in app bundle)
    let julia_cmd = if cfg!(target_os = "macos") {
        // Check if we're running from an app bundle
        if let Ok(exe_path) = std::env::current_exe() {
            if exe_path.to_string_lossy().contains(".app/Contents/MacOS") {
                // We're in an app bundle, use embedded Julia
                let bundle_julia = exe_path
                    .parent().unwrap()  // MacOS
                    .parent().unwrap()  // Contents
                    .join("Resources/julia-wrapper.sh");
                if bundle_julia.exists() {
                    debug!("Using embedded Julia from app bundle");
                    bundle_julia.to_string_lossy().to_string()
                } else {
                    "julia".to_string()
                }
            } else {
                // Development mode - check for embedded Julia in resources
                let dev_julia = Path::new("apps/cedar-bundle/resources/julia-wrapper.sh");
                if dev_julia.exists() {
                    debug!("Using embedded Julia from development resources");
                    dev_julia.to_string_lossy().to_string()
                } else {
                    "julia".to_string()
                }
            }
        } else {
            "julia".to_string()
        }
    } else {
        // On other platforms, use system Julia or check env var
        std::env::var("JULIA_BIN").unwrap_or_else(|_| "julia".to_string())
    };

    // Prefer passing the file path directly to Julia.
    let mut cmd = Command::new(&julia_cmd);
    cmd.arg("--project")
        .arg(script_path.as_os_str())
        .current_dir(run_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    info!("spawning julia");
    let mut child = cmd.spawn().map_err(|e| anyhow::anyhow!("spawn failed: {e}"))?;
    let (t_out, t_err) = spawn_log_threads(&mut child);

    let status = child.wait().map_err(|e| anyhow::anyhow!("wait failed: {e}"))?;
    let out = t_out.join().unwrap_or_default();
    let err = t_err.join().unwrap_or_default();
    let ok = status.success();

    Ok(ToolOutcome {
        ok,
        message: if err.is_empty() { out } else { format!("{out}\n{err}") },
        ..Default::default()
    })
}
