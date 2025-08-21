# OpenAI Key Management Flow

This document describes how Cedar manages OpenAI API keys, ensuring secure provisioning from server to client.

## Overview

Cedar follows a server-provisioned key model where:
1. The OpenAI API key is configured on the server (environment variable)
2. When the Cedar app boots, it fetches the key from the server once
3. The key is cached locally for the session
4. All OpenAI API calls use this provisioned key

This approach ensures:
- Keys are centrally managed and can be rotated on the server
- Clients don't need to manage keys directly
- Keys are never stored in client code or repositories

## Configuration

### Server Side

Set the OpenAI API key on your Cedar server:

```bash
# Required: Set the OpenAI API key
export OPENAI_API_KEY=sk-your-actual-key-here

# Optional: Set the model (defaults to gpt-5)
export OPENAI_MODEL=gpt-5

# Start the Cedar server
cargo run --bin notebook_server
```

The server exposes the key at `GET /config/openai_key` which returns:
```json
{
  "openai_api_key": "sk-...",
  "source": "server"
}
```

### Client Side

Configure the Cedar client to fetch keys from your server:

```bash
# Point to your Cedar server
export CEDAR_SERVER_URL=http://localhost:8080

# Optional: Force refresh of cached key
export CEDAR_REFRESH_KEY=1

# Run the Cedar CLI
cargo run --bin cedar-cli -- agent --user-prompt "Hello"
```

## Key Fetch Flow

1. **On App Startup**: Cedar checks for an OpenAI key in this order:
   - Cached key from previous server fetch (if < 24 hours old)
   - Fresh fetch from server (if `CEDAR_SERVER_URL` is set)
   - Environment variable `OPENAI_API_KEY` (fallback)

2. **Server Fetch**: When fetching from server:
   - Makes GET request to `{CEDAR_SERVER_URL}/config/openai_key`
   - Validates the key format (must start with `sk-` and be >= 40 chars)
   - Caches the key locally at `~/.config/cedar-cli/openai_key.json`
   - Logs success with key fingerprint (first 6 + last 4 chars)

3. **Cache Management**:
   - Keys are cached for 24 hours
   - Set `CEDAR_REFRESH_KEY=1` to force a fresh fetch
   - Cache includes timestamp and source for debugging

## Security Considerations

- **Never commit keys**: OpenAI keys should never be in code or repositories
- **Server-only storage**: Keys are only stored on the server as environment variables
- **Secure transport**: Use HTTPS in production for server communication
- **Key validation**: All keys are validated for correct format before use
- **Logging**: Only key fingerprints are logged, never full keys

## Error Handling

If key provisioning fails, Cedar will show clear error messages:

```
No OpenAI API key available. Please either:
1. Set CEDAR_SERVER_URL to point to a Cedar server with OPENAI_API_KEY configured
2. Set OPENAI_API_KEY environment variable directly
See docs/openai-key-flow.md for details.
```

## Code References

Key components involved in the flow:

- **Server endpoint**: `crates/notebook_server/src/lib.rs` - `get_openai_key()`
- **Client key manager**: `crates/notebook_core/src/key_manager.rs`
- **Integration points**: Search for comments referencing this doc

## Deployment Examples

### Local Development

```bash
# Terminal 1: Start server with key
OPENAI_API_KEY=sk-your-key cargo run --bin notebook_server

# Terminal 2: Run client
CEDAR_SERVER_URL=http://localhost:8080 cargo run --bin cedar-cli -- agent
```

### Production (Render)

1. Set environment variable in Render dashboard:
   - `OPENAI_API_KEY`: Your production key
   - `PORT`: (Render sets automatically)

2. Client configuration:
   ```bash
   export CEDAR_SERVER_URL=https://your-app.onrender.com
   cedar-cli agent --user-prompt "Analyze data"
   ```

### Docker Deployment

```dockerfile
# Server Dockerfile
ENV OPENAI_API_KEY=${OPENAI_API_KEY}
ENV PORT=8080
EXPOSE 8080
CMD ["./notebook_server"]
```

```bash
# Run with key
docker run -e OPENAI_API_KEY=sk-your-key -p 8080:8080 cedar-server
```

## Troubleshooting

### Key not fetching from server

1. Check server is running: `curl http://localhost:8080/health`
2. Verify key is set on server: Check server logs for "OpenAI key requested"
3. Check client can reach server: `curl http://localhost:8080/config/openai_key`

### Cached key issues

```bash
# Clear cached key
rm ~/.config/cedar-cli/openai_key.json

# Force refresh
CEDAR_REFRESH_KEY=1 cedar-cli agent
```

### Invalid key errors

- Ensure key starts with `sk-` and is a valid OpenAI key
- Check for extra whitespace or quotes in environment variable
- Verify key works directly: `curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"`

## Migration from Direct Keys

If migrating from direct key usage:

1. Move key from client `.env` to server environment
2. Update client to use `CEDAR_SERVER_URL` instead of `OPENAI_API_KEY`
3. Test with `CEDAR_REFRESH_KEY=1` to ensure fresh fetch
4. Remove any local `.env` files with keys

## Related Documentation

- [Architecture Overview](./architecture.md) - System design and components
- [External Services](./external-services.md) - Integration with OpenAI and other services
- [README](../README.md) - Quick start and usage
