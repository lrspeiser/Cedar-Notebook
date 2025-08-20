use crate::executors::{TablePreview, ToolOutcome};
use anyhow::{Result, Context};
use duckdb::Connection;
use std::{path::Path};

pub fn run_sql_to_parquet(workdir: &Path, sql: &str) -> Result<ToolOutcome> {
    let db = Connection::open_in_memory()?;
    // Execute multi-statement SQL and try to capture the final row-returning statement
    // For simplicity, we always write the result of the last SELECT to result.parquet
    let statements: Vec<&str> = sql.split(';').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
    let mut last_select: Option<String> = None;
    for stmt in &statements {
        if stmt.to_ascii_lowercase().starts_with("select") {
            last_select = Some((*stmt).to_string());
        } else {
            db.execute(stmt, [])?;
        }
    }
    let parquet_path = workdir.join("result.parquet");
    if let Some(sel) = last_select {
        let copy = format!("COPY ({}) TO '{}' (FORMAT parquet)", sel, parquet_path.display());
        db.execute(&copy, [])?;
    }

    // Build quick preview
    let preview_sql = if parquet_path.exists() {
        format!("SELECT * FROM read_parquet('{}') LIMIT 10", parquet_path.display())
    } else {
        "SELECT 1 as ok LIMIT 1".to_string()
    };

    let mut stmt = db.prepare(&preview_sql)?;
    let mut rows = stmt.query([])?;
    let mut rows_json = vec![];
    while let Some(row) = rows.next()? {
        let mut obj = serde_json::Map::new();
        for (i, col) in row.as_ref().columns().iter().enumerate() {
            let name = col.name().to_string();
            let v = row.get_ref(i)?;
            let vj = match v {
                duckdb::types::ValueRef::Null => serde_json::Value::Null,
                duckdb::types::ValueRef::Int8(x) => (*x as i64).into(),
                duckdb::types::ValueRef::Int16(x) => (*x as i64).into(),
                duckdb::types::ValueRef::Int32(x) => (*x as i64).into(),
                duckdb::types::ValueRef::Int64(x) => (*x as i64).into(),
                duckdb::types::ValueRef::UInt8(x) => (*x as u64).into(),
                duckdb::types::ValueRef::UInt16(x) => (*x as u64).into(),
                duckdb::types::ValueRef::UInt32(x) => (*x as u64).into(),
                duckdb::types::ValueRef::UInt64(x) => (*x as u64).into(),
                duckdb::types::ValueRef::Float(x) => (*x as f64).into(),
                duckdb::types::ValueRef::Double(x) => (*x as f64).into(),
                duckdb::types::ValueRef::Text(s) => String::from_utf8_lossy(s).to_string().into(),
                _ => serde_json::Value::String(format!("{:?}", v)),
            };
            obj.insert(name, vj);
        }
        rows_json.push(serde_json::Value::Object(obj));
    }
    let mut schema = vec![];
    for col in stmt.columns() {
        schema.push((col.name().to_string(), format!("{:?}", col.decl_type())));
    }
    Ok(ToolOutcome{
        ok: true,
        message: "SQL executed".into(),
        preview_json: None,
        table: Some(TablePreview{
            schema, rows: rows_json, row_count: 0, path: Some(parquet_path.to_string_lossy().to_string())
        }),
        stdout_tail: None,
        stderr_tail: None,
    })
}
