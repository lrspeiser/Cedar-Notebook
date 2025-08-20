use crate::executors::{TablePreview, ToolOutcome};
use crate::util::{write_string};
use anyhow::{Result, Context};
use duckdb::{Connection};
use regex::Regex;
use std::{fs, path::{Path, PathBuf}, process::{Command, Stdio}, io::Read, time::Duration};
use std::env;

fn julia_bin() -> String {
    env::var("JULIA_BIN").unwrap_or_else(|_| "julia".to_string())
}

fn ensure_julia_env(root: &Path) -> Result<PathBuf> {
    let env_dir = root.join(".cedar").join("julia_env");
    fs::create_dir_all(&env_dir)?;
    let project_toml = env_dir.join("Project.toml");
    if !project_toml.exists() && env::var("CEDAR_JULIA_AUTO_ADD").unwrap_or_else(|_| "1".into()) == "1" {
        let mut project = String::from("[deps]\n");
        project.push_str("CSV = \"336ed68f-0bac-5ca0-87d4-7b16caf5d00b\"\n");
        project.push_str("DataFrames = \"a93c6f00-e57d-5684-b7b6-d8193f3e46c0\"\n");
        project.push_str("DuckDB = \"a29a1f8d-6c5c-4f0d-bb3e-8f3d1d1a2f9b\"\n");
        project.push_str("Parquet = \"626c502c-15b0-58ad-a749-9eee5b4b9c8d\"\n");
        project.push_str("JSON3 = \"0f8b85d8-7281-11e9-16c2-39a750bddbf1\"\n");
        fs::write(&project_toml, project)?;
    }
    Ok(env_dir)
}

fn tail(s: &str, n: usize) -> String {
    let lines: Vec<&str> = s.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].join("\n")
}

pub fn run_julia_cell(workdir: &Path, code: &str) -> Result<ToolOutcome> {
    fs::create_dir_all(workdir)?;
    let env_dir = ensure_julia_env(&std::env::current_dir()?)?;
    let cell_path = workdir.join("cell.jl");
    write_string(&cell_path, code)?;

    let stdout_path = workdir.join("julia.stdout.txt");
    let stderr_path = workdir.join("julia.stderr.txt");

    // Build wrapper script that activates env and runs the cell
    let wrapper = format!(r#"
import Pkg
try
    Pkg.activate(ENV["JULIA_PROJECT"])
catch
    # fallback: activate current directory
    Pkg.activate(pwd())
end
try
    include(raw"{cell}")
catch e
    @error "Cell errored" exception=(e, catch_backtrace())
    rethrow()
end
"#, cell=cell_path.display());
    let wrapper_path = workdir.join("run_cell.jl");
    write_string(&wrapper_path, &wrapper)?;

    let mut cmd = Command::new(julia_bin());
    cmd.arg("--project").arg(&env_dir);
    cmd.arg(wrapper_path.as_os_str());
    cmd.current_dir(workdir);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = cmd.spawn().with_context(|| "Failed to spawn Julia")?;
    let output = child.wait_with_output().with_context(|| "Failed to wait for Julia")?;
    fs::write(&stdout_path, &output.stdout)?;
    fs::write(&stderr_path, &output.stderr)?;

    let mut preview_json: Option<serde_json::Value> = None;
    let out_str = String::from_utf8_lossy(&output.stdout);
    let err_str = String::from_utf8_lossy(&output.stderr);

    // Extract PREVIEW_JSON block
    let re = Regex::new(r"(?s)```PREVIEW_JSON\s*(\{.*?\})\s*```").unwrap();
    if let Some(cap) = re.captures(&out_str) {
        if let Some(m) = cap.get(1) {
            match serde_json::from_str::<serde_json::Value>(m.as_str()) {
                Ok(v) => preview_json = Some(v),
                Err(_) => {}
            }
        }
    }

    // If result.parquet exists, build a small preview with DuckDB
    let parquet_path = workdir.join("result.parquet");
    let table = if parquet_path.exists() {
        // Use DuckDB to preview first 10 rows and schema
        let conn = Connection::open_in_memory()?;
        let sql = format!("SELECT * FROM read_parquet('{}') LIMIT 10", parquet_path.display());
        let mut stmt = conn.prepare(&sql)?;
        let mut rows_iter = stmt.query([])?;
        let mut rows_json = vec![];
        while let Some(row) = rows_iter.next()? {
            let mut obj = serde_json::Map::new();
            for (i, name) in row.as_ref().column_names().iter().enumerate() {
                let name = (*name).to_string();
                // Very simple type mapping for preview
                let v = row.get_ref(i)?;
                let vj = match v {
                    duckdb::types::ValueRef::Null => serde_json::Value::Null,
                    duckdb::types::ValueRef::Text(s) => String::from_utf8_lossy(s).to_string().into(),
                    _ => serde_json::Value::String(format!("{:?}", v)),
                };
                obj.insert(name, vj);
            }
            rows_json.push(serde_json::Value::Object(obj));
        }
        // Get schema
        let mut schema = vec![];
        for name in stmt.column_names() {
            schema.push((name.to_string(), "unknown".to_string()));
        }
        Some(TablePreview {
            schema,
            rows: rows_json,
            row_count: 0,
            path: Some(parquet_path.to_string_lossy().to_string()),
        })
    } else {
        None
    };

    let ok = output.status.success();
    Ok(ToolOutcome {
        ok,
        message: if ok { "Julia completed".into() } else { "Julia failed".into() },
        preview_json,
        table,
        stdout_tail: Some(tail(&out_str, 80)),
        stderr_tail: Some(tail(&err_str, 80)),
    })
}
