# Security model

- Shell executor is a strict allowlist; unknown commands are denied.
- CWD is constrained to the run workdir; attempts to escape are blocked.
- Timeouts are enforced for shell; Julia failures are captured and returned to the model for self-healing.
- Secrets must come from environment variables; avoid pasting secrets in prompts.
