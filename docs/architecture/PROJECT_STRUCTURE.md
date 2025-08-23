# Project structure

```
.
├── Cargo.toml               # Workspace
├── crates
│   ├── cedar-core           # Core library (agent loop + executors + data)
│   └── cedar-cli            # CLI using cedar-core
├── apps
│   └── cedar-egui           # Desktop app (egui) layered on cedar-core
├── docs                     # Additional docs and ADRs (optional)
├── data                     # Example datasets (small)
│   └── parquet              # Registered datasets end up here by default
└── runs/                    # Only used when CEDAR_ALLOW_OVERRIDE=1
```
