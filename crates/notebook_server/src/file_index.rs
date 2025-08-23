use anyhow::{anyhow, Context, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, process::Command, time::SystemTime};

/// File metadata stored in our index
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndexedFile {
    pub path: String,
    pub name: String,
    pub kind: String,
    pub mtime: i64,
    pub size: Option<u64>,
}

/// Request for searching files
#[derive(Debug, Deserialize)]
pub struct SearchRequest {
    pub query: String,
    pub limit: Option<usize>,
}

/// The file indexer that manages our SQLite database and Spotlight integration
pub struct FileIndexer {
    conn: Connection,
}

// Practical list of data-oriented file types we care about
const SPOTLIGHT_UTIS: &[&str] = &[
    // Tables / spreadsheets
    "public.comma-separated-values-text",            // .csv
    "public.tab-separated-values-text",              // .tsv
    "org.openxmlformats.spreadsheetml.sheet",        // .xlsx
    "com.microsoft.excel.xls",                       // .xls
    "org.oasis-open.opendocument.spreadsheet",       // .ods
    "com.apple.iwork.numbers.sffnumbers",            // Numbers

    // Semi-structured
    "public.json",                                   // .json
    "public.yaml",                                   // .yaml / .yml
    "public.xml",                                    // .xml
    "public.plain-text",                             // .txt

    // Analytics/big-data
    "org.apache.parquet",                            // .parquet
    "org.apache.arrow.file",                         // .feather / .arrow
    "org.apache.avro",                               // .avro

    // Databases
    "public.sqlite3",                                // .sqlite / .db
    "org.duckdb",                                    // .duckdb

    // Documents
    "com.adobe.pdf",                                 // .pdf
    "org.openxmlformats.wordprocessingml.document",  // .docx
    "com.microsoft.word.doc",                        // .doc
    "net.daringfireball.markdown",                   // .md
];

const EXTENSIONS_GUARD: &[&str] = &[
    // tables
    "csv", "tsv", "tab", "psv",
    "xls", "xlsx", "ods", "numbers",
    // semi-structured
    "json", "jsonl", "ndjson", "yaml", "yml", "xml", "txt",
    // analytics/big-data
    "parquet", "feather", "arrow", "orc", "avro",
    // databases
    "sqlite", "sqlite3", "db", "duckdb",
    // documents
    "pdf", "doc", "docx", "md", "markdown",
];

impl FileIndexer {
    /// Create a new file indexer with the given database path
    pub fn new(db_path: &PathBuf) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        let indexer = Self { conn };
        indexer.init_schema()?;
        Ok(indexer)
    }

    /// Initialize the database schema with FTS5 for instant search
    fn init_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;

            CREATE TABLE IF NOT EXISTS files(
                path TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                mtime INTEGER NOT NULL,
                size INTEGER
            );

            -- FTS5 index for instant autocomplete (searches both filename and path)
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts
            USING fts5(name, path, content='');

            -- Indexes for quick sorting and filtering
            CREATE INDEX IF NOT EXISTS idx_files_name ON files(name);
            CREATE INDEX IF NOT EXISTS idx_files_mtime ON files(mtime DESC);
            CREATE INDEX IF NOT EXISTS idx_files_kind ON files(kind);
            
            -- Track indexing metadata
            CREATE TABLE IF NOT EXISTS index_meta(
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at INTEGER
            );
            "#,
        )?;
        Ok(())
    }

    /// Seed the index from Spotlight - this is the initial bulk indexing
    pub fn seed_from_spotlight(&self, scope: Option<String>) -> Result<usize> {
        let onlyin = scope.or_else(|| {
            dirs::home_dir().map(|p| p.to_string_lossy().to_string())
        }).ok_or_else(|| anyhow!("Could not determine home directory"))?;

        eprintln!("[FileIndexer] Starting Spotlight seed from: {}", onlyin);
        
        let query = Self::build_spotlight_bootstrap_query();
        let files = self.run_spotlight(&query, Some(&onlyin))?;
        let count = files.len();
        
        eprintln!("[FileIndexer] Found {} files, indexing...", count);
        self.upsert_files(&files)?;
        
        // Record when we last indexed
        self.conn.execute(
            "INSERT OR REPLACE INTO index_meta(key, value, updated_at) VALUES(?1, ?2, ?3)",
            params!["last_seed", &onlyin, SystemTime::now().duration_since(SystemTime::UNIX_EPOCH)?.as_secs() as i64],
        )?;
        
        eprintln!("[FileIndexer] Successfully indexed {} files", count);
        Ok(count)
    }

    /// Insert or update files in the database
    fn upsert_files(&self, rows: &[IndexedFile]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        {
            let mut up = tx.prepare(
                r#"INSERT INTO files(path, name, kind, mtime, size)
                   VALUES (?1, ?2, ?3, ?4, ?5)
                   ON CONFLICT(path) DO UPDATE SET
                     name=excluded.name,
                     kind=excluded.kind,
                     mtime=excluded.mtime,
                     size=excluded.size"#,
            )?;

            for r in rows {
                up.execute(params![&r.path, &r.name, &r.kind, r.mtime, r.size])?;
                
                // Sync to FTS index
                let rowid: Option<i64> = tx
                    .query_row("SELECT rowid FROM files WHERE path=?1", params![&r.path], |c| {
                        c.get(0)
                    })
                    .optional()?;
                
                if let Some(id) = rowid {
                    // Delete any prior FTS row for this rowid
                    tx.execute("DELETE FROM files_fts WHERE rowid=?1", params![id])?;
                    // Insert new FTS row
                    tx.execute(
                        "INSERT INTO files_fts(rowid, name, path) VALUES(?1, ?2, ?3)",
                        params![id, &r.name, &r.path],
                    )?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Instant prefix search using FTS5
    pub fn search_instant(&self, prefix: &str, limit: usize) -> Result<Vec<IndexedFile>> {
        if prefix.trim().is_empty() {
            // If empty query, return recent files
            return self.get_recent_files(limit);
        }

        // Escape quotes and build FTS query
        let needle = prefix.replace('"', " ").replace('\'', " ");
        // Search both name and path for maximum flexibility
        let fts_query = format!(r#"(name: "{}*" OR path: "*{}*")"#, needle, needle);

        let mut stmt = self.conn.prepare(
            r#"
            SELECT DISTINCT f.path, f.name, f.kind, f.mtime, f.size
            FROM files_fts fts
            JOIN files f ON f.rowid = fts.rowid
            WHERE files_fts MATCH ?1
            ORDER BY 
                -- Prioritize name matches over path matches
                CASE WHEN LOWER(f.name) LIKE LOWER(?2 || '%') THEN 0 ELSE 1 END,
                f.mtime DESC
            LIMIT ?3
            "#,
        )?;

        let rows = stmt
            .query_map(params![fts_query, prefix, limit as i64], |c| {
                Ok(IndexedFile {
                    path: c.get(0)?,
                    name: c.get(1)?,
                    kind: c.get(2)?,
                    mtime: c.get(3)?,
                    size: c.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(rows)
    }

    /// Get recently modified files when no search query
    pub fn get_recent_files(&self, limit: usize) -> Result<Vec<IndexedFile>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT path, name, kind, mtime, size
            FROM files
            ORDER BY mtime DESC
            LIMIT ?1
            "#,
        )?;

        let rows = stmt
            .query_map(params![limit as i64], |c| {
                Ok(IndexedFile {
                    path: c.get(0)?,
                    name: c.get(1)?,
                    kind: c.get(2)?,
                    mtime: c.get(3)?,
                    size: c.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(rows)
    }

    /// Fallback to Spotlight when local index has no results
    pub fn spotlight_search_fallback(&self, query: &str) -> Result<Vec<IndexedFile>> {
        let onlyin = dirs::home_dir()
            .map(|p| p.to_string_lossy().to_string())
            .ok_or_else(|| anyhow!("Could not determine home directory"))?;

        // Build a name-based Spotlight query
        let trimmed = query.trim();
        let (opener, closer) = if trimmed.contains(' ') { 
            ("*", "*")  // substring search for multi-word
        } else { 
            ("", "*")   // prefix search for single word
        };

        let spotlight_query = Self::build_spotlight_name_query(trimmed, opener, closer);
        let mut files = self.run_spotlight(&spotlight_query, Some(&onlyin))?;
        
        // Limit results to prevent overwhelming
        files.truncate(100);
        
        // Merge into our database for future instant access
        if !files.is_empty() {
            self.upsert_files(&files)?;
        }

        Ok(files)
    }

    /// Run a Spotlight (mdfind) query
    fn run_spotlight(&self, query: &str, onlyin: Option<&str>) -> Result<Vec<IndexedFile>> {
        // Use -0 (NUL) separator for robustness with paths containing newlines
        let mut args = vec!["-0"];
        if let Some(dir) = onlyin {
            args.push("-onlyin");
            args.push(dir);
        }
        args.push(query);

        let output = Command::new("mdfind")
            .args(&args)
            .output()
            .with_context(|| "Failed to run mdfind (Spotlight). Is this macOS?")?;

        if !output.status.success() {
            return Err(anyhow!(
                "mdfind failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        let mut files = Vec::new();
        for path_bytes in output.stdout.split(|b| *b == 0u8) {
            if path_bytes.is_empty() {
                continue;
            }
            
            let path = String::from_utf8_lossy(path_bytes).into_owned();
            
            // Skip if path doesn't exist (Spotlight index might be stale)
            let metadata = match std::fs::metadata(&path) {
                Ok(m) => m,
                Err(_) => continue,
            };
            
            let name = std::path::Path::new(&path)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| path.clone());

            let mtime = metadata.modified()
                .ok()
                .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);

            let size = Some(metadata.len());
            let kind = Self::guess_kind_from_path(&path);

            files.push(IndexedFile {
                path,
                name,
                kind,
                mtime,
                size,
            });
        }
        
        Ok(files)
    }

    /// Build the bootstrap Spotlight query for initial seeding
    fn build_spotlight_bootstrap_query() -> String {
        // Query by UTI (Uniform Type Identifier) - most reliable
        let uti_conditions: Vec<String> = SPOTLIGHT_UTIS
            .iter()
            .map(|uti| format!(r#"kMDItemContentTypeTree == "{}""#, uti))
            .collect();

        // Also query by file extension as fallback
        let ext_conditions: Vec<String> = EXTENSIONS_GUARD
            .iter()
            .map(|ext| format!(r#"kMDItemFSName == "*.{}""#, ext))
            .collect();

        format!(
            "(({}) || ({})) && kMDItemFSSize > 0",
            uti_conditions.join(" || "),
            ext_conditions.join(" || ")
        )
    }

    /// Build a Spotlight query for searching by filename
    fn build_spotlight_name_query(name: &str, opener: &str, closer: &str) -> String {
        // Escape quotes in the search term
        let safe_name = name.replace('"', " ").replace('\'', " ");
        
        // Combine with our file type filter
        let type_filter = Self::build_spotlight_type_filter();
        
        format!(
            r#"({}) && kMDItemFSName == "{}{}{}""#,
            type_filter, opener, safe_name, closer
        )
    }

    /// Build just the file type filter portion of a Spotlight query
    fn build_spotlight_type_filter() -> String {
        let uti_conditions: Vec<String> = SPOTLIGHT_UTIS
            .iter()
            .map(|uti| format!(r#"kMDItemContentTypeTree == "{}""#, uti))
            .collect();

        let ext_conditions: Vec<String> = EXTENSIONS_GUARD
            .iter()
            .map(|ext| format!(r#"kMDItemFSName == "*.{}""#, ext))
            .collect();

        format!(
            "(({}) || ({}))",
            uti_conditions.join(" || "),
            ext_conditions.join(" || ")
        )
    }

    /// Guess file kind from extension
    fn guess_kind_from_path(path: &str) -> String {
        let ext = std::path::Path::new(path)
            .extension()
            .map(|e| e.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        
        match ext.as_str() {
            "csv" => "CSV",
            "tsv" | "tab" | "psv" => "TSV",
            "xls" => "Excel (Legacy)",
            "xlsx" => "Excel",
            "ods" => "OpenDocument",
            "numbers" => "Numbers",
            "json" | "jsonl" | "ndjson" => "JSON",
            "yaml" | "yml" => "YAML",
            "xml" => "XML",
            "txt" => "Text",
            "parquet" => "Parquet",
            "feather" | "arrow" => "Arrow",
            "orc" => "ORC",
            "avro" => "Avro",
            "sqlite" | "sqlite3" | "db" => "SQLite",
            "duckdb" => "DuckDB",
            "pdf" => "PDF",
            "doc" => "Word (Legacy)",
            "docx" => "Word",
            "md" | "markdown" => "Markdown",
            _ => "Other",
        }
        .to_string()
    }

    /// Get statistics about the index
    pub fn get_stats(&self) -> Result<serde_json::Value> {
        let total_count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM files",
            [],
            |row| row.get(0),
        )?;

        let mut stmt = self.conn.prepare(
            "SELECT kind, COUNT(*) as cnt FROM files GROUP BY kind ORDER BY cnt DESC LIMIT 20"
        )?;
        let by_kind: Vec<(String, i64)> = stmt.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

        let last_seed: Option<(String, i64)> = self.conn
            .query_row(
                "SELECT value, updated_at FROM index_meta WHERE key = 'last_seed'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;

        Ok(serde_json::json!({
            "total_files": total_count,
            "by_kind": by_kind.into_iter().map(|(k, v)| {
                serde_json::json!({"kind": k, "count": v})
            }).collect::<Vec<_>>(),
            "last_indexed": last_seed.map(|(path, ts)| {
                serde_json::json!({
                    "path": path,
                    "timestamp": ts,
                    "timestamp_human": chrono::DateTime::<chrono::Utc>::from_timestamp(ts, 0)
                        .map(|dt| dt.format("%Y-%m-%d %H:%M:%S UTC").to_string())
                        .unwrap_or_else(|| "Unknown".to_string())
                })
            }),
        }))
    }
}
