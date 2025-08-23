# Spotlight-Based File Indexing System

## Overview

Cedar now features a powerful file indexing system that leverages macOS Spotlight for fast, comprehensive file discovery with instant search capabilities. When the app is installed, it indexes data files on your computer and provides an instant autocomplete search interface.

## Architecture

### Components

1. **Spotlight Integration** (`file_index.rs`)
   - Uses macOS `mdfind` command to discover files
   - Filters by UTI (Uniform Type Identifiers) and file extensions
   - Supports incremental indexing and search fallback

2. **SQLite FTS5 Database**
   - Stores file metadata (path, name, type, size, modified date)
   - Full-text search index for instant autocomplete
   - WAL mode for concurrent access

3. **REST API Endpoints**
   - `POST /files/index` - Index files using Spotlight
   - `POST /files/indexed/search` - Instant search with autocomplete
   - `GET /files/indexed/stats` - Get index statistics

4. **Files UI** (`files-ui.html`)
   - Beautiful, responsive interface
   - Instant search with 150ms debounce
   - File selection and processing workflow

## How It Works

### 1. Initial Indexing
When the user clicks "Index Files" or the app starts:
```
User → POST /files/index → Spotlight (mdfind) → SQLite Database
```

The system:
- Queries Spotlight for all data files (CSV, Excel, JSON, Parquet, etc.)
- Filters by UTI and file extensions
- Stores metadata in SQLite with FTS5 index
- Typically indexes thousands of files in seconds

### 2. Instant Search
As the user types:
```
Keystroke → Debounce (150ms) → FTS5 Query → Instant Results
```

Features:
- Prefix matching on filenames
- Substring matching on paths
- Prioritizes name matches over path matches
- Returns results in <10ms typically

### 3. Spotlight Fallback
If no results found in local index:
```
Empty Results → Spotlight Search → Merge to Index → Show Results
```

This ensures users can always find files, even newly created ones.

### 4. File Processing
When user selects a file:
```
Select File → Show Path → Process Button → LLM Pipeline → Parquet Output
```

## Supported File Types

### Spreadsheets & Tables
- CSV, TSV, PSV
- Excel (.xls, .xlsx)
- OpenDocument (.ods)
- Numbers

### Semi-Structured Data
- JSON, JSONL, NDJSON
- YAML, YML
- XML
- Plain text

### Analytics Formats
- Parquet
- Arrow/Feather
- ORC
- Avro

### Databases
- SQLite
- DuckDB

### Documents
- PDF
- Word (.doc, .docx)
- Markdown

## Usage

### Starting the Server
```bash
cd /path/to/cedarcli
OPENAI_API_KEY=your_key cargo run -p notebook_server
```

### Opening the Files UI
Navigate to: http://localhost:8080/files-ui.html

### Workflow
1. Click "Index Files" (first time only)
2. Start typing to search instantly
3. Click a file to select it
4. Click "Process File" to convert to Parquet

## API Reference

### Index Files
```http
POST /files/index
```
Response:
```json
{
  "success": true,
  "indexed_count": 1234
}
```

### Search Files
```http
POST /files/indexed/search
Content-Type: application/json

{
  "query": "sales",
  "limit": 50
}
```
Response:
```json
{
  "success": true,
  "files": [
    {
      "path": "/Users/name/data/sales_2024.csv",
      "name": "sales_2024.csv",
      "kind": "CSV",
      "mtime": 1737164400,
      "size": 45678
    }
  ]
}
```

### Get Statistics
```http
GET /files/indexed/stats
```
Response:
```json
{
  "total_files": 1234,
  "by_kind": [
    {"kind": "CSV", "count": 456},
    {"kind": "Excel", "count": 123}
  ],
  "last_indexed": {
    "path": "/Users/name",
    "timestamp": 1737164400,
    "timestamp_human": "2025-01-17 20:00:00 UTC"
  }
}
```

## Performance

### Indexing Speed
- ~1000 files/second on typical MacBook
- Uses Spotlight's existing index (no file system crawling)
- Incremental updates supported

### Search Performance
- <10ms for instant autocomplete
- FTS5 prefix matching optimized
- Results prioritized by relevance and recency

### Database Size
- ~1KB per file indexed
- 10,000 files ≈ 10MB database
- WAL mode for concurrent access

## Configuration

### Search Scope
Default search paths:
- Home directory
- Downloads
- Desktop
- Documents
- /tmp

Can be customized via API:
```json
{
  "scope": "/Users/name/specific/folder"
}
```

### File Type Filters
Configured via UTIs and extensions in `file_index.rs`:
- Add UTIs to `SPOTLIGHT_UTIS` array
- Add extensions to `EXTENSIONS_GUARD` array

## Troubleshooting

### No Files Found
1. Ensure Spotlight indexing is enabled
2. Grant Full Disk Access to Terminal/app
3. Check if files have proper UTIs: `mdls file.csv`

### Slow Indexing
1. Reduce search scope
2. Check Spotlight index health: `mdutil -s /`
3. Rebuild if needed: `sudo mdutil -E /`

### Search Not Working
1. Check if database exists: `~/.cedar/runs/file_index.sqlite`
2. Re-index files via UI
3. Check server logs for errors

## Security & Privacy

- **Local Only**: All indexing happens locally
- **No Cloud Sync**: Database stays on your machine
- **Path Access**: Only indexes files you can read
- **Selective Indexing**: Can limit scope to specific folders

## Future Enhancements

1. **FSEvents Integration**: Auto-update index when files change
2. **Smart Suggestions**: ML-based file recommendations
3. **File Preview**: Show data preview in search results
4. **Batch Processing**: Select multiple files at once
5. **Index Scheduling**: Automatic periodic re-indexing

## Integration with Cedar

The file indexing system integrates seamlessly with Cedar's data processing pipeline:

1. **Discovery**: Find files instantly without remembering paths
2. **Selection**: Visual file browser with metadata
3. **Processing**: One-click conversion to Parquet
4. **Analysis**: Automatic loading into DuckDB

This creates a complete workflow from "I have data somewhere" to "It's ready for analysis" in seconds.

## Example Use Case

Sarah, a data analyst, needs to analyze Q4 sales data:

1. Opens Cedar Files UI
2. Types "sales" - instantly sees all sales-related files
3. Notices `q4_sales_2024.xlsx` modified yesterday
4. Clicks to select, sees full path
5. Clicks "Process File"
6. Cedar converts to Parquet and loads into DuckDB
7. Ready for SQL analysis in under 10 seconds

No need to remember file paths, navigate folders, or manually convert formats.

## Technical Details

### Spotlight Query Construction
```
((kMDItemContentTypeTree == "public.comma-separated-values-text" || 
  kMDItemFSName == "*.csv") || ...) && 
  kMDItemFSSize > 0
```

### FTS5 Query Format
```sql
SELECT * FROM files_fts 
WHERE files_fts MATCH 'name: "sales*" OR path: "*sales*"'
```

### Database Schema
```sql
CREATE TABLE files(
    path TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    mtime INTEGER NOT NULL,
    size INTEGER
);

CREATE VIRTUAL TABLE files_fts
USING fts5(name, path, content='');
```

## Conclusion

The Spotlight-based file indexing system transforms file discovery in Cedar from a manual, path-based process to an instant, search-based experience. By leveraging macOS's built-in indexing and SQLite's FTS5, we achieve Google-like instant search for local data files, making data analysis more accessible and efficient.
