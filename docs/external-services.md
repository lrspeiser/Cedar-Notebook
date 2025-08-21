# External services and keys (OpenAI)

- The Cedar server provides OpenAI API keys to clients via GET /config/openai_key endpoint
- Clients fetch the key once at startup and cache it locally for the session
- After fetching, the app calls OpenAI directly (Responses API) with Authorization header
- See docs/openai-key-flow.md for complete key management strategy and configuration
- Code touching keys must include a comment pointing to docs/openai-key-flow.md
