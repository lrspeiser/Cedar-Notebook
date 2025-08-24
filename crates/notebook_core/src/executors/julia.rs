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

// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

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
    // Log the code being executed
    eprintln!("[JULIA] Executing code in directory: {}", run_dir.display());
    eprintln!("[JULIA] Code length: {} bytes", code.len());
    if code.len() < 500 {
        eprintln!("[JULIA] Code: {}", code);
    } else {
        eprintln!("[JULIA] Code (first 500 chars): {}...", &code[..500]);
    }
    
    // Write a temporary script; if you already do this differently, keep your path.
    let script_path = run_dir.join("cell.jl");
    fs::write(&script_path, code)?;
    debug!(script = %script_path.display(), "wrote Julia cell");
    eprintln!("[JULIA] Script written to: {}", script_path.display());

    // First check for JULIA_BIN environment variable on all platforms
    let julia_cmd = if let Ok(julia_bin) = std::env::var("JULIA_BIN") {
        debug!("Using Julia from JULIA_BIN: {}", julia_bin);
        julia_bin
    } else if cfg!(target_os = "macos") {
        // Check for embedded Julia (in app bundle)
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
                // Try relative to current working directory first
                let dev_julia = Path::new("apps/cedar-bundle/resources/julia-wrapper.sh");
                if dev_julia.exists() {
                    debug!("Using embedded Julia from development resources (relative path)");
                    dev_julia.canonicalize().unwrap_or(dev_julia.to_path_buf()).to_string_lossy().to_string()
                } else {
                    // Try relative to executable location
                    let exe_dir = exe_path.parent().unwrap();
                    let julia_from_exe = exe_dir.join("../../../apps/cedar-bundle/resources/julia-wrapper.sh");
                    if julia_from_exe.exists() {
                        debug!("Using embedded Julia from development resources (exe relative)");
                        julia_from_exe.canonicalize().unwrap_or(julia_from_exe).to_string_lossy().to_string()
                    } else {
                        debug!("No bundled Julia found, falling back to system julia");
                        "julia".to_string()
                    }
                }
            }
        } else {
            "julia".to_string()
        }
    } else {
        // On other platforms, use system Julia
        "julia".to_string()
    };

    // Pass the script file directly to Julia
    let mut cmd = Command::new(&julia_cmd);
    cmd.arg(script_path.as_os_str())
        .current_dir(run_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    eprintln!("[JULIA] Command: {} {}", julia_cmd, script_path.display());
    eprintln!("[JULIA] Working directory: {}", run_dir.display());
    info!("spawning julia");
    let mut child = cmd.spawn().map_err(|e| {
        eprintln!("[JULIA ERROR] Failed to spawn Julia process: {}", e);
        anyhow::anyhow!("spawn failed: {e}")
    })?;
    let (t_out, t_err) = spawn_log_threads(&mut child);

    let status = child.wait().map_err(|e| anyhow::anyhow!("wait failed: {e}"))?;
    let out = t_out.join().unwrap_or_default();
    let err = t_err.join().unwrap_or_default();
    let ok = status.success();
    
    eprintln!("[JULIA] Execution completed with status: {} (ok={})", status, ok);
    if !out.is_empty() {
        let out_preview = if out.len() < 500 { 
            out.clone() 
        } else { 
            format!("{}...", &out[..500])
        };
        eprintln!("[JULIA] Stdout ({} bytes): {}", out.len(), out_preview);
    }
    if !err.is_empty() {
        let err_preview = if err.len() < 500 { 
            err.clone() 
        } else { 
            format!("{}...", &err[..500])
        };
        eprintln!("[JULIA] Stderr ({} bytes): {}", err.len(), err_preview);
    }

    // Check if the error is about missing packages
    let message = if err.contains("Package") && err.contains("not found") {
        // Extract package name if possible
        let package_hint = err.lines()
            .find(|line| line.contains("Package") && line.contains("not found"))
            .unwrap_or(&err);
        format!("Julia package error: {}\nHint: Install the missing package using: using Pkg; Pkg.add(\"PackageName\")\n{}", package_hint, out)
    } else if err.is_empty() {
        out.clone()
    } else {
        format!("{out}\n{err}")
    };
    
    Ok(ToolOutcome {
        ok,
        message,
        stderr_tail: if !err.is_empty() { Some(err) } else { None },
        stdout_tail: if !out.is_empty() { Some(out) } else { None },
        ..Default::default()
    })
}
