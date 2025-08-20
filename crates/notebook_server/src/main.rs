use axum::{routing::get, Router};
use std::net::SocketAddr;
use tracing_subscriber::{fmt, EnvFilter};

async fn health() -> &'static str { "ok" }

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    fmt().with_env_filter(filter).init();

    let app = Router::new()
        .route("/healthz", get(health));

    // Placeholder address; in production use config/env
    let addr: SocketAddr = "127.0.0.1:8080".parse().unwrap();
    tracing::info!(%addr, "notebook_server listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
