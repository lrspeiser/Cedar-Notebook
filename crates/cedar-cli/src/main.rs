use anyhow::{Result, Context};
use clap::{Parser, Subcommand};
use cedar_core::agent_loop::{agent_loop, AgentConfig};
use cedar_core::runs::{create_new_run, list_runs};
use cedar_core::util::{default_runs_root, env_flag};
use cedar_core::executors::sql_duckdb::run_sql_to_parquet;
use cedar_core::data::registry::DatasetRegistry;
use std::{path::{PathBuf, Path}, fs, io::Read};
use tracing_subscriber::{EnvFilter, fmt};

#[derive(Parser, Debug)]
#[command(version, about="CedarCLI — End‑to‑End LLM Agent Loop for Data & Compute")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Override runs dir (requires CEDAR_ALLOW_OVERRIDE=1)
    #[arg(long)]
    runs_dir: Option<PathBuf>,

    /// Override workdir (requires CEDAR_ALLOW_OVERRIDE=1)
    #[arg(long)]
    workdir: Option<PathBuf>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Environment doctor checks
    Doctor,
    /// Start an agent loop for a single turn sequence
    Agent {
        #[arg(long)]
        user_prompt: String,
    },
    /// Ingest a local CSV via Julia -> Parquet
    Ingest {
        #[arg(long)]
        path: PathBuf,
    },
    /// Step-by-step pipeline tester (dry-run supported)
    PipelineTest {
        #[arg(long)]
        path: PathBuf,
        #[arg(long, default_value_t=false)]
        dry_run: bool,
    },
    /// Minimal HTTP UI (smoke test)
    Ui {
        #[arg(long, default_value="127.0.0.1:7878")]
        addr: String,
    },
    /// Search cards across runs
    CardsSearch {
        #[arg(long)]
        query: String,
        #[arg(long, default_value_t=50)]
        limit: usize,
    },
    /// Inspect runs (summaries)
    RunsInspect {
        #[arg(long, default_value_t=20)]
        limit: usize,
        #[arg(long, default_value_t=false)]
        details: bool,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    install_tracing();
    dotenvy::dotenv().ok();
    let cli = Cli::parse();

    let runs_root = if env_flag("CEDAR_ALLOW_OVERRIDE") {
        cli.runs_dir.clone().or_else(|| default_runs_root().ok())
    } else {
        default_runs_root().ok()
    }.expect("runs root unavailable");

    match cli.command {
        Commands::Doctor => cmd_doctor().await,
        Commands::Agent { user_prompt } => cmd_agent(&runs_root, &user_prompt).await,
        Commands::Ingest { path } => cmd_ingest(&runs_root, path).await,
        Commands::PipelineTest { path, dry_run } => cmd_pipeline_test(&runs_root, path, dry_run).await,
        Commands::Ui { addr } => cmd_ui(addr).await,
        Commands::CardsSearch { query, limit } => cmd_cards_search(&runs_root, &query, limit).await,
        Commands::RunsInspect { limit, details } => cmd_runs_inspect(&runs_root, limit, details).await,
    }
}

fn install_tracing() {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    fmt().with_env_filter(filter).init();
}

async fn cmd_doctor() -> Result<()> {
    println!("CedarCLI doctor:");
    println!(" - Rust: ok (compiled)");
    // Try shell-allowed commands to show versions
    for cmd in ["cargo --version", "julia --version", "git --version", "python --version"] {
        let out = std::process::Command::new("bash").arg("-lc").arg(cmd).output();
        match out {
            Ok(o) => {
                let s = String::from_utf8_lossy(&o.stdout);
                println!("   $ {} -> {}", cmd, s.trim());
            }
            Err(e) => println!("   $ {} -> error: {}", cmd, e),
        }
    }
    Ok(())
}

async fn cmd_agent(runs_root: &Path, user_prompt: &str) -> Result<()> {
    let run = create_new_run(Some(runs_root))?;
    // If CEDAR_RELAY_URL is set, we route via relay and use APP_SHARED_TOKEN for auth.
    let relay_url = std::env::var("CEDAR_RELAY_URL").ok();
    let app_shared_token = std::env::var("APP_SHARED_TOKEN").ok();

    // OPENAI_API_KEY remains required for direct provider calls; if using relay, we log when key is absent.
    let openai_api_key = match std::env::var("OPENAI_API_KEY") {
        Ok(v) => v,
        Err(_) => {
            if relay_url.is_some() {
                // No provider key needed in client when using relay
                String::from("RELAY_MODE")
            } else {
                anyhow::bail!("OPENAI_API_KEY missing and CEDAR_RELAY_URL not set")
            }
        }
    };

    let cfg = AgentConfig {
        openai_api_key,
        openai_model: std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".into()),
        openai_base: std::env::var("OPENAI_BASE").ok(),
        relay_url,
        app_shared_token,
    };
    agent_loop(&run.dir, user_prompt, 30, cfg).await
}

async fn cmd_ingest(runs_root: &Path, path: PathBuf) -> Result<()> {
    let run = create_new_run(Some(runs_root))?;
    let file = path.canonicalize()?;
    let fname = file.file_name().unwrap().to_string_lossy().to_string();
    let code = format!(r#"
using CSV, DataFrames, Parquet
df = CSV.read(raw"{file}", DataFrame; missingstring="")
first(df, 5) |> println
Parquet.write("result.parquet", df)
println("```PREVIEW_JSON")
println("{{\"summary\":\"Ingested file: {fname}\",\"columns\":", names(df), ",\"rows\":5}}")
println("```")
"#, file=file.display(), fname=fname);
    let out = cedar_core::executors::julia::run_julia_cell(&run.dir, &code)?;
    println!("{}", out.message);
    if let Some(table) = out.table {
        // Register under data/parquet/
        let reg = DatasetRegistry::default_under_repo(&std::env::current_dir()?) ;
        let dst = reg.register_parquet(&fname.replace('.','_'), Path::new(&table.path.unwrap()))?;
        println!("Registered dataset -> {}", dst.display());
    }
    Ok(())
}

async fn cmd_pipeline_test(_runs_root: &Path, path: PathBuf, dry_run: bool) -> Result<()> {
    println!("Pipeline test for: {}", path.display());
    if dry_run {
        println!("(dry-run) Would read CSV with CSV.jl -> Parquet and register. Then validate with DuckDB.");
    } else {
        // Minimal runnable example: run a SQL preview using DuckDB
        let tempdir = tempfile::tempdir()?;
        let sql = format!("SELECT 1 as ok, '{}' as file LIMIT 1", path.display());
        let _ = run_sql_to_parquet(tempdir.path(), &sql)?;
        println!("Wrote result.parquet in {}", tempdir.path().display());
    }
    Ok(())
}

async fn cmd_ui(addr: String) -> Result<()> {
    use axum::{routing::get, Router};
    async fn health() -> &'static str { "ok" }
    async fn index() -> String { "CedarCLI UI (smoke test). Try /healthz".into() }

    let app = Router::new()
        .route("/", get(index))
        .route("/healthz", get(health));

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    println!("UI listening on http://{}", addr);
    axum::serve(listener, app).await?;
    Ok(())
}

async fn cmd_cards_search(runs_root: &Path, query: &str, limit: usize) -> Result<()> {
    let mut count = 0usize;
    for entry in walkdir::WalkDir::new(runs_root).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() && entry.path().extension().map(|e| e=="json").unwrap_or(false) {
            let path = entry.path();
            let mut s = String::new();
            fs::File::open(path)?.read_to_string(&mut s)?;
            if s.to_lowercase().contains(&query.to_lowercase()) {
                println!("{}", path.display());
                count += 1;
                if count >= limit { break; }
            }
        }
    }
    println!("Matched {} card(s).", count);
    Ok(())
}

async fn cmd_runs_inspect(runs_root: &Path, limit: usize, details: bool) -> Result<()> {
    let runs = list_runs(limit)?;
    println!("Last {} run(s) under {}", runs.len(), runs_root.display());
    for r in runs {
        let cards_dir = r.dir.join("cards");
        let n_cards = std::fs::read_dir(&cards_dir).map(|it| it.count()).unwrap_or(0);
        println!("- {}  [{} card(s)]  {}", r.id, n_cards, r.dir.display());
        if details {
            for entry in std::fs::read_dir(&cards_dir)? {
                let e = entry?;
                println!("    {}", e.path().display());
            }
        }
    }
    Ok(())
}
