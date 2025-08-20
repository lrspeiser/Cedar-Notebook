# External services and keys (OpenAI)

- The CLI fetches/caches OPENAI_API_KEY from a token-protected endpoint when CEDAR_KEY_URL + APP_SHARED_TOKEN are set.
- After fetching, the app calls OpenAI directly (Responses API) with Authorization header.
- See README.md → "OpenAI configuration and key flow" for full details.
- Code touching keys must include a comment pointing to this doc.
