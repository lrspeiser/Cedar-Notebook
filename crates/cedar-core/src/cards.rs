use serde::{Serialize, Deserialize};
use chrono::{Utc, DateTime};
use std::{fs, path::PathBuf};
use anyhow::Result;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AssistantCard {
    pub ts_utc: DateTime<Utc>,
    pub run_id: String,
    pub title: String,
    pub summary: String,
    pub details: serde_json::Value,
    pub files: Vec<String>,
}

impl AssistantCard {
    pub fn save(&self, run_dir: &PathBuf) -> Result<PathBuf> {
        let ts = self.ts_utc.format("%Y%m%d-%H%M%S").to_string();
        let file = run_dir.join("cards").join(format!("{}-{}.json", ts, self.title.replace(' ', "_")));
        fs::create_dir_all(file.parent().unwrap())?;
        fs::write(&file, serde_json::to_vec_pretty(self)?)?;
        Ok(file)
    }
}
