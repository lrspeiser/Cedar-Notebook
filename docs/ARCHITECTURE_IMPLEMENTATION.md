# Cedar Architecture Implementation Guide

## Core Principle: STRICT FRONTEND/BACKEND SEPARATION

### Frontend (HTML/JavaScript) - THIN CLIENT ONLY
**Location:** `apps/desktop/index.html` and other HTML files

**ALLOWED:**
- Collect user input (text, file selections)
- Send raw data to backend endpoints
- Display responses from backend
- Basic UI state management (tabs, visibility)

**FORBIDDEN:**
- Construct prompts for LLM
- Process files beyond reading for preview
- Make decisions about data handling
- Calculate or format data for processing
- ANY business logic whatsoever

### Backend (Rust) - ALL BUSINESS LOGIC
**Location:** `crates/notebook_server/src/main.rs` and related files

**RESPONSIBILITIES:**
- API key management (fetched from server per `docs/openai-key-flow.md`)
- Model selection (GPT-5 hardcoded - see README.md)
- Prompt construction for LLM
- File processing strategies
- Dataset context management
- All LLM interactions
- Julia code execution
- Shell command execution

## How to Implement New Features

### 1. Adding a New User Input Feature

**Frontend Changes:**
```javascript
// In index.html - ONLY collect input
async function submitQuery(fileInfo = null) {
    const requestBody = {
        prompt: userInput,      // Raw user text
        file_info: fileInfo,    // File metadata only
        // Add new field here for new input type
        new_feature: userSelection
    };
    
    // Send to backend - no processing
    const response = await fetch(`${API_URL}/commands/submit_query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
    });
}
```

**Backend Changes:**
```rust
// In main.rs - Add field to request struct
#[derive(Deserialize)]
struct SubmitQueryBody {
    prompt: Option<String>,
    file_info: Option<FileInfo>,
    new_feature: Option<String>,  // New field
}

// In handle_submit_query - Process the new input
async fn handle_submit_query(body: SubmitQueryBody) -> anyhow::Result<SubmitQueryResponse> {
    // Backend decides what to do with new_feature
    if let Some(feature_value) = body.new_feature {
        // Construct appropriate prompt
        // Apply business logic
        // Format for LLM
    }
}
```

### 2. File Processing

**WRONG WAY (Frontend doing business logic):**
```javascript
// DON'T DO THIS IN FRONTEND
const prompt = `Process this file with these steps:
1. Load the CSV
2. Convert to Parquet
3. Run analysis`;
```

**RIGHT WAY (Backend handles everything):**
```javascript
// Frontend - just send file info
const fileInfo = {
    name: file.name,
    path: filePath,  // If available
    size: file.size,
    preview: firstNLines  // Optional, for display only
};
await submitQuery(fileInfo);
```

```rust
// Backend - constructs the prompt
if let Some(file_info) = &body.file_info {
    // Backend decides processing strategy
    full_prompt.push_str("I have a CSV file that needs processing...");
    // Backend adds all instructions
    full_prompt.push_str("1. Load the CSV\n2. Convert to Parquet...");
}
```

## Key Files and Their Roles

### Configuration & Documentation
- `docs/openai-key-flow.md` - API key management strategy
- `README.md` - GPT-5 model documentation
- `start_cedar_server.sh` - Server startup with API key fetching

### Backend Core
- `crates/notebook_server/src/main.rs` - Main HTTP endpoints and business logic
- `crates/notebook_server/src/lib.rs` - Server configuration and routes
- `crates/notebook_core/src/agent_loop.rs` - LLM interaction logic
- `crates/notebook_core/src/key_manager.rs` - API key fetching from server

### Frontend UI
- `apps/desktop/index.html` - Main desktop app UI (THIN CLIENT)
- `/Desktop/cedar_agent.html` - Standalone web UI (THIN CLIENT)

## Common Mistakes to Avoid

### ❌ DON'T: Let frontend construct prompts
```javascript
// WRONG - Frontend shouldn't know about Julia or data processing
const prompt = "Write Julia code to process this CSV...";
```

### ✅ DO: Send raw input to backend
```javascript
// RIGHT - Backend decides what to do
const requestBody = { file_info: { name: "data.csv", ... } };
```

### ❌ DON'T: Process data in frontend
```javascript
// WRONG - Frontend doing calculations
const sizeInMB = file.size / 1048576;
const formattedSize = `${sizeInMB.toFixed(2)} MB`;
```

### ✅ DO: Let backend handle formatting
```rust
// RIGHT - Backend handles all formatting
let size_display = if size > 1_048_576 {
    format!("{:.2} MB", size as f64 / 1_048_576.0)
} else {
    format!("{:.2} KB", size as f64 / 1024.0)
};
```

## Testing Changes

1. **Build Backend:**
```bash
cd ~/Projects/cedarcli
cargo build --release --bin notebook_server
```

2. **Start Server with API Key:**
```bash
./start_cedar_server.sh
```

3. **Test with Desktop App:**
```bash
open /Applications/cedar-desktop.app
```

4. **Test API Directly:**
```bash
# Test text query
curl -X POST http://localhost:8080/commands/submit_query \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is 2+2?"}'

# Test file processing
curl -X POST http://localhost:8080/commands/submit_query \
  -H "Content-Type: application/json" \
  -d '{"file_info": {"name": "test.csv", "path": "/path/to/file"}}'
```

## Model Configuration

**IMPORTANT:** GPT-5 is hardcoded as the model. DO NOT CHANGE THIS.

Location: `crates/notebook_server/src/main.rs`
```rust
// gpt-5 is the latest model - see README.md for current model documentation
openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".to_string()),
```

## API Key Flow

The system follows a server-provisioned key model:
1. Server fetches key from relay service or environment
2. Key is used for all LLM calls
3. Frontend NEVER handles API keys directly

See `docs/openai-key-flow.md` for complete details.

## Future Development

When adding new features:
1. Start with the backend - define what data you need from the user
2. Add fields to `SubmitQueryBody` for that data
3. Implement processing logic in `handle_submit_query`
4. Update frontend to collect and send the raw data
5. Test end-to-end with the desktop app

Remember: Frontend is just a form that sends data to backend. Backend does EVERYTHING else.
