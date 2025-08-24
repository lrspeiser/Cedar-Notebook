// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use anyhow::{Result, Context};
use serde_json::json;

// Smoke test for direct OpenAI Responses API call.
// Configuration details and rationale (direct calls, optional key fetch via server):
//   See README.md → "OpenAI configuration and key flow".
// This binary intentionally avoids other deps so it can validate credentials and API shape quickly.
#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();

    // Fetch key if needed from server
    if std::env::var("OPENAI_API_KEY").is_err() {
        if let (Ok(key_url), Ok(token)) = (std::env::var("CEDAR_KEY_URL"), std::env::var("APP_SHARED_TOKEN")) {
            let client = reqwest::Client::new();
            let resp = client.get(&key_url).header("x-app-token", token).send().await.context("fetch key")?;
            let status = resp.status();
            let v: serde_json::Value = resp.json().await.context("key json")?;
            let key = v.get("openai_api_key").and_then(|x| x.as_str()).context("key missing")?;
            std::env::set_var("OPENAI_API_KEY", key);
            eprintln!("[smoke] fetched key: status={}", status);
        } else {
            anyhow::bail!("OPENAI_API_KEY not set and no CEDAR_KEY_URL/APP_SHARED_TOKEN provided");
        }
    }

    let key = std::env::var("OPENAI_API_KEY").context("OPENAI_API_KEY missing")?;
    let model = std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-5".into());
    let base = std::env::var("OPENAI_BASE").unwrap_or_else(|_| "https://api.openai.com".into());
    let url = format!("{}/v1/responses", base.trim_end_matches('/'));

    let payload = json!({
        "model": model,
        "input": [{"role":"user","content":"Say hello from cedar-smoke."}],
    });

    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {}", key))
        .json(&payload)
        .send()
        .await
        .context("send")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();

    eprintln!("[smoke] status={} bytes={}", status, text.len());
    println!("{}", text);
    Ok(())
}
