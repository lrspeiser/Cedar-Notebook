// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
  app_lib::run();
}
