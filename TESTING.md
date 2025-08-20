# Testing CedarCLI

- Unit tests:
  ```bash
  cargo test -- --nocapture
  ```

- Smoke tests for the agent loop (requires `OPENAI_API_KEY`):
  ```bash
  cargo run --bin cedar-cli -- agent --user-prompt "Say hi, then ask me for a CSV."
  ```

- Ingest without LLM (pipeline tester):
  ```bash
  cargo run --bin cedar-cli -- pipeline-test --path data-test/"Cars Datasets 2025.csv" --dry-run
  ```
