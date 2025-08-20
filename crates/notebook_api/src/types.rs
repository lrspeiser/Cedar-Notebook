use specta::Type;
use serde::{Serialize, Deserialize};

#[derive(Type, Serialize, Deserialize, Clone, Debug)]
pub struct RunId(pub String);

#[derive(specta::Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct RunSummary {
    pub id: String,
    pub path: String,
}

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct CardSummary {
    pub path: String,
    pub title: Option<String>,
}

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct TableSpec {
    pub kind: TableSpecKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arrow_ipc_base64: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parquet: Option<ParquetHandle>,
}

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
#[serde(rename_all = "snake_case")]
pub enum TableSpecKind { ArrowIpc, ParquetHandle }

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct ParquetHandle { pub id: String }

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct PlotSpec { pub kind: PlotKind, pub spec: serde_json::Value }

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
#[serde(rename_all = "snake_case")]
pub enum PlotKind { VegaLite }

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct RichSpec { pub kind: RichKind, pub content: String }

#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
#[serde(rename_all = "snake_case")]
pub enum RichKind { Html, Markdown }

// Acknowledgements & events
#[derive(Type, serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct RunAck { pub run_id: String, pub ok: bool, pub message: Option<String> }

#[derive(Type, Serialize, Deserialize, Clone, Debug)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RunEvent {
    Started { run_id: String, ts: i64 },
    Progress { run_id: String, step: String, pct: f32 },
    ArtifactAdded { run_id: String, path: String, mime: String },
    Finished { run_id: String, ok: bool },
}
