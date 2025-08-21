use std::process::Command;
use std::thread;
use std::time::Duration;
use std::net::SocketAddr;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🌲 Cedar Agent Starting...");
    
    // Start the backend server in a separate tokio task
    let server_handle = tokio::spawn(async {
        start_backend_server().await
    });
    
    // Give the server a moment to start
    tokio::time::sleep(Duration::from_secs(2)).await;
    
    // Open the web UI in the default browser
    open_web_interface();
    
    // Add a system tray icon or dock icon handler here if needed
    println!("Cedar is running at http://localhost:8080");
    println!("Press Ctrl+C to stop the server");
    
    // Wait for the server to complete (it won't unless there's an error)
    server_handle.await??;
    
    Ok(())
}

async fn start_backend_server() -> Result<(), Box<dyn std::error::Error>> {
    use axum::{
        routing::{get, post},
        Router,
    };
    use tower_http::cors::{CorsLayer, Any};
    
    println!("Starting Cedar backend server on http://localhost:8080");
    
    // Create the router with all the endpoints from notebook_server
    // This is a simplified version - in production, we'd import the actual routes
    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/commands/submit_query", post(handle_query))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any)
        );
    
    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    
    println!("✅ Server running on http://localhost:8080");
    
    axum::serve(listener, app).await?;
    
    Ok(())
}

// Placeholder for the actual query handler
// In production, this would call the notebook_server functions
async fn handle_query(
    axum::Json(body): axum::Json<serde_json::Value>
) -> axum::Json<serde_json::Value> {
    // This would call the actual notebook_server::handle_submit_query
    axum::Json(serde_json::json!({
        "status": "ok",
        "message": "Query processing would happen here"
    }))
}

fn open_web_interface() {
    println!("Opening Cedar web interface...");
    
    // Get the path to the bundled HTML file
    let html_path = if cfg!(debug_assertions) {
        // In development, use the local file
        "apps/web-ui/app-enhanced.html"
    } else {
        // In production, use the bundled resource
        // This would be in the app bundle's Resources folder
        "Cedar.app/Contents/Resources/web-ui/app-enhanced.html"
    };
    
    // Open the HTML file in the default browser
    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .arg(html_path)
            .spawn()
            .expect("Failed to open web interface");
    }
    
    #[cfg(target_os = "windows")]
    {
        Command::new("cmd")
            .args(&["/C", "start", html_path])
            .spawn()
            .expect("Failed to open web interface");
    }
    
    #[cfg(target_os = "linux")]
    {
        Command::new("xdg-open")
            .arg(html_path)
            .spawn()
            .expect("Failed to open web interface");
    }
}
