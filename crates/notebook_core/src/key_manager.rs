use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Manages OpenAI API key fetching and caching from server
/// See docs/openai-key-flow.md for complete key management strategy
#[derive(Debug, Clone)]
pub struct KeyManager {
    cache_path: PathBuf,
    server_url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct CachedKey {
    api_key: String,
    source: String,
    cached_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ServerKeyResponse {
    openai_api_key: String,
    source: String,
}

impl KeyManager {
    /// Create a new KeyManager with the default cache location
    pub fn new() -> Result<Self> {
        let cache_dir = directories::ProjectDirs::from("com", "CedarAI", "CedarCLI")
            .context("Could not determine config directory")?
            .config_dir()
            .to_path_buf();
        
        std::fs::create_dir_all(&cache_dir)?;
        
        Ok(Self {
            cache_path: cache_dir.join("openai_key.json"),
            server_url: std::env::var("CEDAR_SERVER_URL").ok(),
        })
    }
    
    /// Fetch OpenAI API key from server and cache it locally
    /// This is called once at app startup to provision the key for the session
    /// See docs/openai-key-flow.md for the complete flow
    pub async fn fetch_key_from_server(&self) -> Result<String> {
        let server_url = self.server_url
            .clone()
            .or_else(|| std::env::var("CEDAR_SERVER_URL").ok())
            .unwrap_or_else(|| "http://localhost:8080".to_string());
        
        let url = format!("{}/config/openai_key", server_url.trim_end_matches('/'));
        
        eprintln!("[cedar] Fetching OpenAI key from server: {}", url);
        
        // Make HTTP request to server
        let client = reqwest::Client::new();
        let response = client
            .get(&url)
            .send()
            .await
            .context("Failed to connect to Cedar server")?;
        
        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("Server returned error {}: {}", status, error_text);
        }
        
        let key_response: ServerKeyResponse = response
            .json()
            .await
            .context("Failed to parse server response")?;
        
        // Validate the key
        if !Self::is_valid_openai_key(&key_response.openai_api_key) {
            anyhow::bail!("Server returned invalid OpenAI key format");
        }
        
        // Cache the key locally
        let cached = CachedKey {
            api_key: key_response.openai_api_key.clone(),
            source: key_response.source,
            cached_at: chrono::Utc::now(),
        };
        
        let json = serde_json::to_string_pretty(&cached)?;
        std::fs::write(&self.cache_path, json)
            .context("Failed to cache OpenAI key")?;
        
        let fingerprint = Self::key_fingerprint(&key_response.openai_api_key);
        eprintln!("[cedar] Successfully fetched and cached OpenAI key from server (fingerprint: {})", fingerprint);
        
        Ok(key_response.openai_api_key)
    }
    
    /// Get the OpenAI API key, fetching from server if needed
    /// This follows the priority order:
    /// 1. Cached key from previous server fetch (if recent)
    /// 2. Fresh fetch from server (if server URL is configured)
    /// 3. Environment variable fallback
    pub async fn get_api_key(&self) -> Result<String> {
        // Check if we should force refresh
        let force_refresh = std::env::var("CEDAR_REFRESH_KEY")
            .map(|v| v == "1" || v.to_lowercase() == "true")
            .unwrap_or(false);
        
        // Try to use cached key if not forcing refresh
        if !force_refresh {
            if let Ok(cached_key) = self.read_cached_key() {
                // Check if cache is less than 24 hours old
                let age = chrono::Utc::now() - cached_key.cached_at;
                if age.num_hours() < 24 {
                    eprintln!("[cedar] Using cached OpenAI key from server (age: {} hours)", age.num_hours());
                    return Ok(cached_key.api_key);
                }
            }
        }
        
        // Try to fetch from server if configured
        if self.server_url.is_some() || std::env::var("CEDAR_SERVER_URL").is_ok() {
            match self.fetch_key_from_server().await {
                Ok(key) => return Ok(key),
                Err(e) => {
                    eprintln!("[cedar] Warning: Failed to fetch key from server: {}", e);
                    // Continue to fallback options
                }
            }
        }
        
        // Fall back to environment variable
        if let Ok(key) = std::env::var("OPENAI_API_KEY") {
            if Self::is_valid_openai_key(&key) {
                eprintln!("[cedar] Using OpenAI key from environment variable");
                return Ok(key);
            }
        }
        
        anyhow::bail!(
            "No OpenAI API key available. Please either:\n\
            1. Set CEDAR_SERVER_URL to point to a Cedar server with OPENAI_API_KEY configured\n\
            2. Set OPENAI_API_KEY environment variable directly\n\
            See docs/openai-key-flow.md for details."
        )
    }
    
    /// Read cached key from disk
    fn read_cached_key(&self) -> Result<CachedKey> {
        if !self.cache_path.exists() {
            anyhow::bail!("No cached key found");
        }
        
        let content = std::fs::read_to_string(&self.cache_path)?;
        let cached: CachedKey = serde_json::from_str(&content)?;
        
        if !Self::is_valid_openai_key(&cached.api_key) {
            anyhow::bail!("Cached key is invalid");
        }
        
        Ok(cached)
    }
    
    /// Validate that a string looks like a valid OpenAI API key
    fn is_valid_openai_key(key: &str) -> bool {
        key.starts_with("sk-") && key.len() >= 40
    }
    
    /// Create a fingerprint of the key for logging (first 6 and last 4 chars)
    fn key_fingerprint(key: &str) -> String {
        if key.len() >= 10 {
            format!("{}...{}", &key[..6], &key[key.len()-4..])
        } else {
            "invalid".to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_validation() {
        assert!(KeyManager::is_valid_openai_key("sk-abc123def456ghi789jkl012mno345pqr678stu901vwx234"));
        assert!(!KeyManager::is_valid_openai_key("invalid-key"));
        assert!(!KeyManager::is_valid_openai_key("sk-short"));
        assert!(!KeyManager::is_valid_openai_key(""));
    }

    #[test]
    fn test_key_fingerprint() {
        let key = "sk-abc123def456ghi789jkl012mno345pqr678stu901vwx234";
        let fingerprint = KeyManager::key_fingerprint(key);
        assert_eq!(fingerprint, "sk-abc...x234");
    }
}
