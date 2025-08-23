# Cedar Desktop Application

The Cedar Desktop application provides a native macOS experience with the full web UI capabilities while maintaining all business logic in the Rust backend.

## Architecture

The desktop app follows a strict separation of concerns:
- **UI Layer**: HTML/JavaScript for presentation only
- **Business Logic**: All processing happens in the Rust backend
- **Communication**: HTTP API calls to localhost:8080

## Features

The desktop app includes all features from the web UI:
- **Research Tab**: Natural language queries with LLM responses
- **Data Tab**: File upload with drag & drop support
- **History Tab**: Query history tracking
- **Julia Code Execution**: Automatic code generation and execution
- **Dataset Management**: Upload, query, and delete datasets

## Installation

### From DMG (Recommended)

1. Download the latest DMG from releases
2. Open the DMG file
3. Drag Cedar Desktop to Applications
4. Launch from Applications folder

### Building from Source

```bash
# Prerequisites
- Rust 1.75+
- Node.js 18+
- Tauri CLI

# Build steps
cd apps/desktop
npm install
npm run tauri:build -- --bundles dmg
```

The DMG will be created at:
```
target/release/bundle/dmg/cedar-desktop_*.dmg
```

## Usage

### Starting the Backend Server

The desktop app requires the backend server to be running:

```bash
cd /path/to/cedarcli
./start_cedar_server.sh
```

The server will:
1. Load environment variables from `.env`
2. Fetch API key from onrender if configured
3. Start on http://localhost:8080

### Launching the App

1. Ensure the backend server is running
2. Launch Cedar Desktop from Applications
3. The app will automatically connect to localhost:8080

### Server Connection Status

The app displays connection status in the header:
- **Green dot**: Connected to backend
- **Red dot**: Backend offline

If offline, the app shows clear instructions for starting the server.

## Configuration

### API Key Management

The app supports multiple API key sources (in priority order):

1. **Onrender Server** (Default)
   ```env
   CEDAR_KEY_URL=https://cedar-notebook.onrender.com/v1/key
   APP_SHARED_TOKEN=403-298-09345-023495
   ```

2. **Environment Variable**
   ```bash
   export OPENAI_API_KEY=your-key-here
   ```

3. **Configuration File**
   ```
   ~/Library/Preferences/com.CedarAI.cedar-cli/.env
   ```

4. **macOS Keychain**
   ```bash
   security add-generic-password -s 'cedar-cli' -a 'OPENAI_API_KEY' -w 'your-key'
   ```

### Environment Files

The desktop app loads environment from:
1. App bundle resources (`.env.desktop`)
2. User home directory (`~/.cedar/.env`)
3. Project root (`.env`)

## Testing

### Backend API Testing

Test all backend endpoints before using the app:

```bash
python3 test_backend_api.py
```

This verifies:
- Server connectivity
- API key configuration
- All HTTP endpoints
- Query processing

### Detailed LLM Testing

Test LLM integration with detailed output:

```bash
python3 test_llm_detailed.py
```

Shows:
- Query processing steps
- Generated Julia code
- Execution results
- Response times

## Debugging

### Console Logs

Open developer tools in the desktop app:
- Press `Cmd+Option+I`
- Check Console tab for debug output

### Server Logs

The backend server outputs detailed logs including:
- API key fetching status
- Query processing steps
- Julia execution output
- Error messages

## Troubleshooting

### "Backend Offline" Error

1. Check server is running: `curl http://localhost:8080/health`
2. Start server if needed: `./start_cedar_server.sh`
3. Click "Retry Connection" in the app

### "No API Key" Error

1. Check environment: `echo $OPENAI_API_KEY`
2. Set in `.env` file or environment
3. Restart server with proper configuration

### Query Failures

1. Check server logs for errors
2. Verify API key is valid
3. Test with simple query: "What is 2+2?"

## Development

### Project Structure

```
apps/desktop/
├── src-tauri/          # Rust backend integration
│   ├── src/
│   │   └── lib.rs     # Environment loading
│   └── Cargo.toml
├── src/                # UI components
├── index.html          # Main UI (full web interface)
├── package.json
└── vite.config.ts
```

### Key Components

- **lib.rs**: Loads environment configuration
- **index.html**: Complete web UI with all features
- **Backend API**: All business logic in Rust

### Building for Distribution

```bash
# Build optimized DMG
npm run tauri:build -- --bundles dmg

# Output location
ls -la target/release/bundle/dmg/
```

## API Endpoints

The desktop app uses these backend endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Server health check |
| `/commands/submit_query` | POST | Submit LLM query |
| `/datasets/upload` | POST | Upload files |
| `/datasets` | GET | List datasets |
| `/datasets/{id}` | DELETE | Delete dataset |

## Security

- API keys are never exposed in the UI
- All processing happens server-side
- Secure communication over localhost
- Keys cached locally with proper permissions

## Performance

- Response times: 1-5 seconds for queries
- File uploads: Depends on file size
- Julia execution: Sub-second for most operations
- Memory usage: ~100MB for UI, backend varies

## Future Enhancements

- [ ] Embedded backend server (no separate process)
- [ ] Offline mode with cached responses
- [ ] Direct file system access
- [ ] Native OS notifications
- [ ] Auto-update mechanism
