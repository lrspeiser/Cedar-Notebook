#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_run_shell_simple() {
        let dir = tempdir().unwrap();
        let result = run_shell(dir.path(), "echo hello", None, None).unwrap();
        assert!(result.ok);
        assert_eq!(result.message.trim(), "hello");
    }

    #[test]
    fn test_run_shell_stderr() {
        let dir = tempdir().unwrap();
        let result = run_shell(dir.path(), ">&2 echo hello", None, None).unwrap();
        assert!(result.ok);
        assert_eq!(result.message.trim(), "hello");
    }

    #[test]
    fn test_run_shell_timeout() {
        let dir = tempdir().unwrap();
        let result = run_shell(dir.path(), "sleep 5", None, Some(1)).unwrap();
        assert!(!result.ok);
        assert!(result.message.contains("Timed out"));
    }
}

use std::{
    io::{BufRead, BufReader},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::Duration,
};
use tracing::{debug, info, warn};
use wait_timeout::ChildExt;

use crate::executors::ToolOutcome;

fn spawn_log_threads(child: &mut Child) -> (thread::JoinHandle<String>, thread::JoinHandle<String>) {
    // stdout
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

    // stderr
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

#[tracing::instrument(
    skip_all,
    fields(run_dir = %run_dir.display(), cmd = %cmdline, cwd = ?cwd, timeout = ?timeout_secs)
)]
pub fn run_shell(
    run_dir: &Path,
    cmdline: &str,
    cwd: Option<&str>,
    timeout_secs: Option<u64>,
) -> anyhow::Result<ToolOutcome> {
    // Cross-platform shell launcher
    #[cfg(target_os = "windows")]
    let mut cmd = {
        let mut c = Command::new("cmd");
        c.args(["/C", cmdline]);
        c
    };
    #[cfg(not(target_os = "windows"))]
    let mut cmd = {
        let mut c = Command::new("bash");
        c.args(["-lc", cmdline]);
        c
    };

    let workdir = cwd.map(PathBuf::from).unwrap_or_else(|| run_dir.to_path_buf());
    debug!(workdir = %workdir.display(), "preparing shell command");
    cmd.current_dir(workdir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    info!("spawning shell command");
    let mut child = cmd.spawn().map_err(|e| anyhow::anyhow!("spawn failed: {e}"))?;
    let (t_out, t_err) = spawn_log_threads(&mut child);

    // Wait with optional timeout
    let status = if let Some(secs) = timeout_secs {
        let dur = Duration::from_secs(secs);
        match child.wait_timeout(dur).map_err(|e| anyhow::anyhow!(e))? {
            Some(status) => status,
            None => {
                warn!("timeout after {secs}s; terminating process");
                let _ = child.kill();
                let _ = child.wait();
                let out = t_out.join().unwrap_or_default();
                let err = t_err.join().unwrap_or_default();
                return Ok(ToolOutcome {
                    ok: false,
                    message: format!("Timed out after {secs}s\n{out}{err}"),
                    ..Default::default()
                });
            }
        }
    } else {
        child.wait().map_err(|e| anyhow::anyhow!("wait failed: {e}"))?
    };

    let out = t_out.join().unwrap_or_default();
    let err = t_err.join().unwrap_or_default();
    let ok = status.success();

    Ok(ToolOutcome {
        ok,
        message: if err.is_empty() { out } else { format!("{out}\n{err}") },
        ..Default::default()
    })
}
