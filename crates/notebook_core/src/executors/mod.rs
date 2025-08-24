
// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

pub mod julia;
pub mod shell;
pub mod sql_duckdb;

use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TablePreview {
    pub schema: Vec<(String, String)>,
    pub rows: Vec<serde_json::Value>,
    pub row_count: usize,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ToolOutcome {
    pub ok: bool,
    pub message: String,
    pub preview_json: Option<serde_json::Value>,
    pub table: Option<TablePreview>,
    pub stdout_tail: Option<String>,
    pub stderr_tail: Option<String>,
}
