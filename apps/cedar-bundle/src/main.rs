use std::process::Command;
use std::time::Duration;
use std::path::PathBuf;
use std::env;
use std::net::TcpListener;

// macOS-specific imports for app activation
#[cfg(target_os = "macos")]
use cocoa::appkit::{NSApp, NSApplication, NSApplicationActivationPolicy};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🌲 Cedar Agent Starting...");
    
    // Set up macOS app activation to stop dock bouncing
    #[cfg(target_os = "macos")]
    unsafe {
        let app = NSApp();
        app.setActivationPolicy_(NSApplicationActivationPolicy::NSApplicationActivationPolicyRegular);
        // Activate the app and mark it as finished launching
        app.activateIgnoringOtherApps_(cocoa::base::YES);
        // Tell macOS we're done launching to stop the bouncing
        app.finishLaunching();
    }
    
    // Set up embedded Julia environment if running from app bundle
    setup_embedded_julia();
    
    // Check if port is already in use
    if is_port_in_use(8080) {
        println!("Port 8080 is already in use. Attempting to use it anyway...");
        // Try to connect to existing server
        if check_server_health().await {
            println!("Existing Cedar server found. Opening web interface...");
            open_web_interface();
            // Exit gracefully since server is already running
            return Ok(());
        } else {
            println!("Port is in use but server is not responding. Please free the port and restart.");
            return Err("Port 8080 is already in use by another application".into());
        }
    }
    
    // Start the backend server in a separate tokio task
    let server_handle = tokio::spawn(async move {
        start_backend_server().await
    });
    
    // Give the server a moment to start
    tokio::time::sleep(Duration::from_secs(3)).await;
    
    // Check if server started successfully
    if !check_server_health().await {
        println!("Warning: Server may not have started correctly.");
    }
    
    // Open the web UI in the default browser
    open_web_interface();
    
    println!("Cedar is running at http://localhost:8080");
    println!("The app will continue running in the background.");
    
    // Wait for the server to complete (it won't unless there's an error)
    match server_handle.await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => {
            eprintln!("Server error: {}", e);
            Err(e as Box<dyn std::error::Error>)
        },
        Err(e) => {
            eprintln!("Task join error: {}", e);
            Err(Box::new(e) as Box<dyn std::error::Error>)
        },
    }
}

fn setup_embedded_julia() {
    // Get the executable path to determine if we're running from an app bundle
    if let Ok(exe_path) = env::current_exe() {
        if exe_path.to_string_lossy().contains(".app/Contents/MacOS") {
            // We're running from an app bundle
            let bundle_path = exe_path
                .parent() // MacOS
                .and_then(|p| p.parent()) // Contents
                .and_then(|p| p.parent()); // Cedar.app
            
            if let Some(bundle) = bundle_path {
                let julia_wrapper = bundle.join("Contents/Resources/julia-wrapper.sh");
                if julia_wrapper.exists() {
                    env::set_var("JULIA_EXECUTABLE", julia_wrapper);
                    println!("Using embedded Julia from app bundle");
                }
            }
        }
    }
}

async fn start_backend_server() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Import the actual notebook server
    println!("Starting Cedar backend server...");
    
    // Run the actual notebook server
    notebook_server::serve().await?;
    
    Ok(())
}

fn open_web_interface() {
    println!("Opening Cedar web interface...");
    
    // Always open the server URL (not the HTML file directly)
    // This ensures the frontend can communicate with the backend
    println!("Opening http://localhost:8080 in browser...");
    
    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .arg("http://localhost:8080")
            .spawn()
            .expect("Failed to open web interface");
    }
    
    #[cfg(target_os = "windows")]
    {
        Command::new("cmd")
            .args(&["/C", "start", "http://localhost:8080"])
            .spawn()
            .expect("Failed to open web interface");
    }
    
    #[cfg(target_os = "linux")]
    {
        Command::new("xdg-open")
            .arg("http://localhost:8080")
            .spawn()
            .expect("Failed to open web interface");
    }
}

fn get_html_path() -> PathBuf {
    // Get the executable path
    if let Ok(exe_path) = env::current_exe() {
        // Check if we're running from an app bundle
        if exe_path.to_string_lossy().contains(".app/Contents/MacOS") {
            // We're in an app bundle
            let resources_path = exe_path
                .parent() // MacOS
                .and_then(|p| p.parent()) // Contents  
                .map(|p| p.join("Resources/web-ui/index.html"));
            
            if let Some(path) = resources_path {
                if path.exists() {
                    return path;
                }
            }
        }
    }
    
    // Fall back to development path
    PathBuf::from("apps/web-ui/index.html")
}

fn is_port_in_use(port: u16) -> bool {
    TcpListener::bind(("127.0.0.1", port)).is_err()
}

async fn check_server_health() -> bool {
    // Simple check using std library
    use std::time::Duration;
    tokio::time::sleep(Duration::from_millis(100)).await;
    
    // Try to connect to the port
    match tokio::net::TcpStream::connect("127.0.0.1:8080").await {
        Ok(_) => true,
        Err(_) => false,
    }
}
