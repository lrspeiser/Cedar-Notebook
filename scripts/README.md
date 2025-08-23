# Cedar Scripts

This directory contains utility scripts for building, testing, and running Cedar.

## Build Scripts

- `build_dmg.sh` - Build the macOS DMG installer
- `build_dmg_simple.sh` - Simplified DMG build script
- `build_macos_dmg.sh` - macOS-specific DMG builder

## Server Management

- `start_cedar_server.sh` - Start the Cedar backend server
- `fix_server_issues.sh` - Fix common server issues
- `launch_cedar_desktop.sh` - Launch the Cedar desktop app

## Setup & Configuration

- `setup_api_key.sh` - Configure OpenAI API key
- `fetch_api_key.sh` - Fetch API key from server

## Data Processing

- `process_csv.sh` - Process CSV files
- `demo_ingestion_workflow.jl` - Julia demo for data ingestion
- `data_ingestion_handler.rs` - Rust data ingestion handler

## Usage Examples

### Start the server
```bash
./scripts/start_cedar_server.sh
```

### Build desktop app
```bash
./scripts/build_dmg.sh
```

### Setup API key
```bash
./scripts/setup_api_key.sh
```
