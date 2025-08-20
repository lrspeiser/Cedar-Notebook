use crate::executors::ToolOutcome;
use crate::util::{is_path_within};
use anyhow::{Result, bail, Context};
use std::{path::{Path, PathBuf}, process::{Command, Stdio}, fs, time::Duration};

fn allowed_prefixes() -> &'static [&'static str] {
    &["cargo", "git", "python", "julia", "rg", "ls", "dir", "echo", "cat", "pwd"]
}

fn is_allowed(cmd: &str) -> bool {
    let trimmed = cmd.trim_start();
    allowed_prefixes().iter().any(|p| trimmed.starts_with(p))
}

fn tail(s: &str, n: usize) -> String {
    let lines: Vec<&str> = s.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].join("\n")
}

pub fn run_shell(workdir: &Path, cmd: &str, cwd: Option<&str>, timeout_secs: Option<u64>) -> Result<ToolOutcome> {
    if !is_allowed(cmd) {
        bail!("Command rejected by allowlist");
    }
    let exec_cwd = if let Some(cwd) = cwd {
        let p = PathBuf::from(cwd);
        if !is_path_within(workdir, &p) { bail!("cwd escapes workdir"); }
        p
    } else {
        workdir.to_path_buf()
    };
    fs::create_dir_all(&exec_cwd)?;

    let stdout_path = workdir.join("shell.stdout.txt");
    let stderr_path = workdir.join("shell.stderr.txt");

    #[cfg(target_os="windows")]
    let mut command = {
        let mut c = Command::new("cmd");
        c.arg("/C").arg(cmd);
        c
    };

    #[cfg(not(target_os="windows"))]
    let mut command = {
        let mut c = Command::new("bash");
        c.arg("-lc").arg(cmd);
        c
    };

    command.current_dir(&exec_cwd);
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let child = command.spawn().with_context(|| "Failed to spawn shell")?;
    let output = if let Some(secs) = timeout_secs {
        match child.wait_with_output_timeout(Duration::from_secs(secs)) {
            Ok(Some(out)) => out,
            Ok(None) => bail!("Timed out"),
            Err(e) => bail!("Failed waiting for process: {}", e),
        }
    } else {
        child.wait_with_output().with_context(|| "Failed to wait for shell")?
    };

    fs::write(&stdout_path, &output.stdout)?;
    fs::write(&stderr_path, &output.stderr)?;

    let out_str = String::from_utf8_lossy(&output.stdout);
    let err_str = String::from_utf8_lossy(&output.stderr);

    let ok = output.status.success();
    // If the command generated common image outputs, register them (best-effort, non-fatal).
    for name in ["plot.png", "plot.svg"] {
        let p = exec_cwd.join(name);
        if p.exists() {
            let mime = if name.ends_with(".png") { "image/png" } else { "image/svg+xml" };
            let entry = crate::runs::ManifestEntry{
                r#type: "image".into(),
                path: name.into(),
                mime: mime.into(),
                title: Some(format!("{}", name)),
                spec_path: None,
                schema_path: None,
                width: None,
                height: None,
                extra: None,
            };
            let _ = crate::runs::append_manifest(workdir, entry);
        }
    }
    Ok(ToolOutcome {
        ok,
        message: format!("shell exited {}", output.status),
        preview_json: None,
        table: None,
        stdout_tail: Some(tail(&out_str, 120)),
        stderr_tail: Some(tail(&err_str, 120)),
    })
}

// Small helper to add timeout support on stable without external crates
trait WaitTimeout {
    fn wait_with_output_timeout(self, dur: Duration) -> std::io::Result<Option<std::process::Output>>;
}
impl WaitTimeout for std::process::Child {
    fn wait_with_output_timeout(mut self, dur: Duration) -> std::io::Result<Option<std::process::Output>> {
        use std::thread;
        use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
        let done = Arc::new(AtomicBool::new(false));
        let done2 = done.clone();
        let id = self.id();
        let handle = thread::spawn(move || {
            let out = self.wait_with_output();
            done2.store(true, Ordering::SeqCst);
            out
        });
        let start = std::time::Instant::now();
        loop {
            if done.load(Ordering::SeqCst) {
                return handle.join().unwrap().map(Some);
            }
            if start.elapsed() > dur {
                // Best effort kill
                #[cfg(unix)]
                unsafe { libc::kill(id as i32, libc::SIGKILL); }
                #[cfg(windows)]
                { /* process will exit shortly */ }
                return Ok(None);
            }
            thread::sleep(std::time::Duration::from_millis(50));
        }
    }
}
