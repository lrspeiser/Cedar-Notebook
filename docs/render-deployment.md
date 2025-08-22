# Cedar on Render - Deployment and Key Management

This document explains how to use Cedar with the Render deployment at https://cedar-notebook.onrender.com

## Overview

The Cedar server is deployed on Render with:
- **OPENAI_API_KEY** environment variable configured on the server
- Token-based authentication for security (`x-app-token` header)
- The `/config/openai_key` endpoint to provision keys to clients

## Client Configuration

### Option 1: Direct Server Usage (Recommended for Production)

Configure your Cedar client to use the Render server directly:

```bash
# Set the server URL
export CEDAR_SERVER_URL="https://cedar-notebook.onrender.com"

# Set the authentication token (get this from your Render dashboard)
export APP_SHARED_TOKEN="your-shared-token-here"

# Run Cedar CLI - it will fetch the OpenAI key from the server
cargo run --bin cedar-cli -- agent --user-prompt "Analyze my data"
```

### Option 2: Fetch Key for Local Development

Fetch the key from Render and use it locally:

```bash
# Set the authentication token
export APP_SHARED_TOKEN="your-shared-token-here"

# Test fetching the key
python3 test_render_key_fetch.py

# The script will show you how to use the fetched key locally
```

## How It Works

1. **Server Side (Render)**:
   - The server has `OPENAI_API_KEY` set as an environment variable
   - The `/config/openai_key` endpoint serves this key (with authentication)
   - All endpoints require the `x-app-token` header for security

2. **Client Side**:
   - The KeyManager fetches the key from the server on startup
   - The key is cached locally for 24 hours
   - All OpenAI API calls use this provisioned key

## Security Features

- **Token Authentication**: All requests require a valid `APP_SHARED_TOKEN`
- **HTTPS Only**: All communication is encrypted
- **Key Caching**: Reduces server calls and improves performance
- **Fingerprint Logging**: Only key fingerprints are logged, never full keys

## Testing the Setup

1. **Check server is accessible**:
```bash
curl -H "x-app-token: your-token" https://cedar-notebook.onrender.com/health
```

2. **Test key endpoint**:
```bash
curl -H "x-app-token: your-token" https://cedar-notebook.onrender.com/config/openai_key
```

3. **Upload a file**:
```bash
curl -X POST \
  -H "x-app-token: your-token" \
  -F "file=@test_data.csv" \
  https://cedar-notebook.onrender.com/datasets/upload
```

## Environment Variables

### On Render Server
- `OPENAI_API_KEY`: Your OpenAI API key
- `APP_SHARED_TOKEN`: Shared secret for authentication
- `PORT`: Set automatically by Render

### On Client
- `CEDAR_SERVER_URL`: https://cedar-notebook.onrender.com
- `APP_SHARED_TOKEN`: Same token as configured on server
- `CEDAR_REFRESH_KEY`: Set to "1" to force refresh cached key

## Troubleshooting

### 401 Unauthorized
- Check that `APP_SHARED_TOKEN` matches between client and server
- Ensure the token is being sent in the `x-app-token` header

### 404 Not Found
- The `/config/openai_key` endpoint may not be deployed yet
- Deploy the latest code with our changes to Render

### 500 Server Error
- Check that `OPENAI_API_KEY` is properly set on Render
- Verify the key format (must start with `sk-` and be >= 40 chars)

## Deployment Updates

To deploy the latest changes to Render:

```bash
# Commit and push changes
git add -A
git commit -m "Add OpenAI key provisioning endpoint"
git push origin main

# Render will automatically deploy from the main branch
```

## Related Documentation

- [OpenAI Key Flow](./openai-key-flow.md) - Complete key management strategy
- [Architecture](./architecture.md) - System design overview
- [External Services](./external-services.md) - Integration details
