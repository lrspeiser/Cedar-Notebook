// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use eframe::egui;
use directories::ProjectDirs;
use std::{fs, path::PathBuf, sync::{Arc, Mutex}};
use notebook_core::{
    key_manager::KeyManager,
    duckdb_metadata::MetadataManager,
};
use notebook_server::{FileIndexer, IndexedFile};
use tokio::runtime::Runtime;

fn main() -> eframe::Result<()> {
    // Initialize tokio runtime for async operations
    let rt = Arc::new(Runtime::new().unwrap());
    
    // Initialize API key on startup
    let key_manager = KeyManager::new().expect("Failed to create KeyManager");
    let rt_clone = rt.clone();
    rt_clone.block_on(async {
        match key_manager.get_api_key().await {
            Ok(key) => {
                std::env::set_var("OPENAI_API_KEY", key);
                eprintln!("[Cedar] API key loaded successfully");
            }
            Err(e) => {
                eprintln!("[Cedar] Warning: Failed to load API key: {}", e);
            }
        }
    });
    
    let options = eframe::NativeOptions {
        initial_window_size: Some(egui::vec2(1200.0, 800.0)),
        ..Default::default()
    };
    
    eframe::run_native(
        "Cedar Desktop",
        options,
        Box::new(move |cc| {
            Box::new(CedarApp::new(cc, rt))
        }),
    )
}

struct CedarApp {
    // Core components
    runtime: Arc<Runtime>,
    metadata_manager: Arc<Mutex<Option<MetadataManager>>>,
    file_indexer: Arc<Mutex<Option<FileIndexer>>>,
    // data_registry: Arc<Mutex<DatasetRegistry>>,  // TODO: Implement when needed
    
    // UI state
    current_tab: Tab,
    query_input: String,
    search_input: String,
    upload_path: String,
    
    // Data
    datasets: Vec<DatasetInfo>,
    search_results: Vec<FileSearchResult>,
    query_history: Vec<QueryResult>,
    
    // Status
    status_message: Option<String>,
    is_processing: bool,
    selected_dataset: Option<String>,
    show_dataset_preview: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum Tab {
    Research,
    Data,
    History,
    Settings,
}

#[derive(Debug, Clone)]
struct DatasetInfo {
    id: String,
    title: String,
    description: Option<String>,
    file_name: String,
    file_type: String,
    row_count: Option<i64>,
    column_count: usize,
    uploaded_at: String,
}

#[derive(Debug, Clone)]
struct FileSearchResult {
    path: PathBuf,
    name: String,
    size: u64,
    modified: String,
}

#[derive(Debug, Clone)]
struct QueryResult {
    query: String,
    response: String,
    timestamp: String,
    artifacts: Vec<String>,
}

impl CedarApp {
    fn new(_cc: &eframe::CreationContext<'_>, runtime: Arc<Runtime>) -> Self {
        // Initialize components
        let project_dirs = ProjectDirs::from("com", "CedarAI", "CedarAI")
            .expect("Failed to get project directories");
        
        let db_path = project_dirs.data_dir().join("metadata.duckdb");
        let metadata_manager = MetadataManager::new(&db_path).ok();
        
        let index_path = project_dirs.data_dir().join("file_index.sqlite");
        let file_indexer = FileIndexer::new(&index_path).ok();
        
        // Dataset registry not used for now
        
        let mut app = Self {
            runtime,
            metadata_manager: Arc::new(Mutex::new(metadata_manager)),
            file_indexer: Arc::new(Mutex::new(file_indexer)),
            // data_registry: Arc::new(Mutex::new(data_registry)),
            
            current_tab: Tab::Research,
            query_input: String::new(),
            search_input: String::new(),
            upload_path: String::new(),
            
            datasets: Vec::new(),
            search_results: Vec::new(),
            query_history: Vec::new(),
            
            status_message: None,
            is_processing: false,
            selected_dataset: None,
            show_dataset_preview: false,
        };
        
        // Load initial data
        app.refresh_datasets();
        app
    }
    
    fn refresh_datasets(&mut self) {
        if let Some(ref mm) = *self.metadata_manager.lock().unwrap() {
            if let Ok(datasets) = mm.list_datasets() {
                self.datasets = datasets.into_iter().map(|d| DatasetInfo {
                    id: d.id,
                    title: d.title,
                    description: d.description,
                    file_name: d.file_name,
                    file_type: d.file_type,
                    row_count: d.row_count,
                    column_count: d.column_info.len(),
                    uploaded_at: d.uploaded_at.to_rfc3339(),
                }).collect();
            }
        }
    }
    
    fn submit_query(&mut self) {
        if self.query_input.trim().is_empty() {
            return;
        }
        
        self.is_processing = true;
        let query = self.query_input.clone();
        
        // Run query in background
        let runtime = self.runtime.clone();
        let metadata_manager = self.metadata_manager.clone();
        
        runtime.spawn(async move {
            // TODO: Implement query processing
            eprintln!("[Cedar] Query: {}", query);
        });
        
        // Add to history
        self.query_history.push(QueryResult {
            query: query.clone(),
            response: "Processing...".to_string(),
            timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
            artifacts: Vec::new(),
        });
        
        self.query_input.clear();
        self.is_processing = false;
    }
    
    fn upload_file(&mut self, path: &str) {
        let path_buf = PathBuf::from(path);
        if !path_buf.exists() {
            self.status_message = Some(format!("File not found: {}", path));
            return;
        }
        
        self.is_processing = true;
        self.status_message = Some(format!("Uploading {}...", path));
        
        // TODO: Implement file upload processing
        
        self.upload_path.clear();
        self.is_processing = false;
        self.refresh_datasets();
    }
    
    fn search_files(&mut self) {
        if self.search_input.trim().is_empty() {
            return;
        }
        
        let indexer = self.file_indexer.clone();
        let query = self.search_input.clone();
        
        if let Some(ref idx) = *indexer.lock().unwrap() {
            if let Ok(results) = idx.search_instant(&query, 20) {
                self.search_results = results.into_iter().map(|f| FileSearchResult {
                    path: PathBuf::from(&f.path),
                    name: f.name,
                    size: f.size as u64,
                    modified: f.modified.to_rfc3339(),
                }).collect();
            }
        }
    }
    
    fn show_dataset_preview(&mut self, dataset_id: &str) {
        self.selected_dataset = Some(dataset_id.to_string());
        self.show_dataset_preview = true;
    }
}

impl eframe::App for CedarApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Top panel with tabs
        egui::TopBottomPanel::top("top_panel").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.selectable_value(&mut self.current_tab, Tab::Research, "🔬 Research");
                ui.selectable_value(&mut self.current_tab, Tab::Data, "📊 Data");
                ui.selectable_value(&mut self.current_tab, Tab::History, "📜 History");
                ui.selectable_value(&mut self.current_tab, Tab::Settings, "⚙️ Settings");
                
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if self.is_processing {
                        ui.spinner();
                    }
                    if let Some(ref msg) = self.status_message {
                        ui.label(msg);
                    }
                });
            });
        });
        
        // Main content
        egui::CentralPanel::default().show(ctx, |ui| {
            match self.current_tab {
                Tab::Research => self.show_research_tab(ui),
                Tab::Data => self.show_data_tab(ui),
                Tab::History => self.show_history_tab(ui),
                Tab::Settings => self.show_settings_tab(ui),
            }
        });
        
        // Dataset preview modal
        if self.show_dataset_preview {
            egui::Window::new("Dataset Preview")
                .collapsible(false)
                .resizable(true)
                .show(ctx, |ui| {
                    if let Some(ref dataset_id) = self.selected_dataset {
                        if let Some(dataset) = self.datasets.iter().find(|d| d.id == *dataset_id) {
                            ui.heading(&dataset.title);
                            ui.separator();
                            
                            ui.label(format!("File: {}", dataset.file_name));
                            ui.label(format!("Type: {}", dataset.file_type));
                            if let Some(rows) = dataset.row_count {
                                ui.label(format!("Rows: {}", rows));
                            }
                            ui.label(format!("Columns: {}", dataset.column_count));
                            ui.label(format!("Uploaded: {}", dataset.uploaded_at));
                            
                            if let Some(ref desc) = dataset.description {
                                ui.separator();
                                ui.label("Description:");
                                ui.label(desc);
                            }
                        }
                    }
                    
                    ui.separator();
                    if ui.button("Close").clicked() {
                        self.show_dataset_preview = false;
                    }
                });
        }
    }
}

impl CedarApp {
    fn show_research_tab(&mut self, ui: &mut egui::Ui) {
        ui.heading("Research Assistant");
        ui.separator();
        
        // Query input area
        ui.horizontal(|ui| {
            ui.label("Query:");
            let response = ui.text_edit_singleline(&mut self.query_input);
            if (response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)))
                || ui.button("Submit").clicked() {
                self.submit_query();
            }
        });
        
        ui.separator();
        
        // File search
        ui.horizontal(|ui| {
            ui.label("Search files:");
            if ui.text_edit_singleline(&mut self.search_input).changed() {
                self.search_files();
            }
        });
        
        // Search results
        if !self.search_results.is_empty() {
            ui.separator();
            ui.label("Search Results:");
            egui::ScrollArea::vertical().show(ui, |ui| {
                for result in &self.search_results {
                    ui.group(|ui| {
                        ui.label(&result.name);
                        ui.label(format!("Path: {}", result.path.display()));
                        ui.label(format!("Size: {} bytes", result.size));
                        if ui.button("Use in query").clicked() {
                            self.query_input.push_str(&format!(" {}", result.path.display()));
                        }
                    });
                }
            });
        }
    }
    
    fn show_data_tab(&mut self, ui: &mut egui::Ui) {
        ui.heading("Data Management");
        ui.separator();
        
        // Upload section
        ui.horizontal(|ui| {
            ui.label("Upload file:");
            ui.text_edit_singleline(&mut self.upload_path);
            if ui.button("Browse").clicked() {
                if let Some(path) = rfd::FileDialog::new().pick_file() {
                    self.upload_path = path.display().to_string();
                }
            }
            if ui.button("Upload").clicked() && !self.upload_path.is_empty() {
                self.upload_file(&self.upload_path);
            }
        });
        
        ui.separator();
        
        // Refresh button
        if ui.button("Refresh Datasets").clicked() {
            self.refresh_datasets();
        }
        
        // Dataset list
        ui.label(format!("Datasets ({})", self.datasets.len()));
        egui::ScrollArea::vertical().show(ui, |ui| {
            for dataset in &self.datasets {
                ui.group(|ui| {
                    ui.horizontal(|ui| {
                        ui.label(&dataset.title);
                        ui.label(format!("({})", dataset.file_type));
                        if ui.button("Preview").clicked() {
                            self.show_dataset_preview(&dataset.id);
                        }
                    });
                    ui.label(format!("File: {}", dataset.file_name));
                    if let Some(rows) = dataset.row_count {
                        ui.label(format!("{} rows × {} columns", rows, dataset.column_count));
                    }
                });
            }
        });
    }
    
    fn show_history_tab(&mut self, ui: &mut egui::Ui) {
        ui.heading("Query History");
        ui.separator();
        
        if self.query_history.is_empty() {
            ui.label("No queries yet");
        } else {
            egui::ScrollArea::vertical().show(ui, |ui| {
                for entry in self.query_history.iter().rev() {
                    ui.group(|ui| {
                        ui.label(format!("[{}]", entry.timestamp));
                        ui.label(format!("Q: {}", entry.query));
                        ui.separator();
                        ui.label(format!("A: {}", entry.response));
                        
                        if !entry.artifacts.is_empty() {
                            ui.separator();
                            ui.label("Artifacts:");
                            for artifact in &entry.artifacts {
                                ui.label(format!("  • {}", artifact));
                            }
                        }
                    });
                }
            });
        }
    }
    
    fn show_settings_tab(&mut self, ui: &mut egui::Ui) {
        ui.heading("Settings");
        ui.separator();
        
        // API Key status
        ui.group(|ui| {
            ui.label("API Key Status:");
            if std::env::var("OPENAI_API_KEY").is_ok() {
                ui.colored_label(egui::Color32::GREEN, "✓ Configured");
            } else {
                ui.colored_label(egui::Color32::RED, "✗ Not configured");
                if ui.button("Fetch from server").clicked() {
                    let runtime = self.runtime.clone();
                    runtime.spawn(async {
                        if let Ok(key_manager) = KeyManager::new() {
                            match key_manager.fetch_key_from_server().await {
                                Ok(key) => {
                                    std::env::set_var("OPENAI_API_KEY", key);
                                    eprintln!("[Cedar] API key fetched successfully");
                                }
                                Err(e) => {
                                    eprintln!("[Cedar] Failed to fetch API key: {}", e);
                                }
                            }
                        }
                    });
                }
            }
        });
        
        ui.separator();
        
        // File indexing
        ui.group(|ui| {
            ui.label("File Index:");
            if ui.button("Rebuild file index").clicked() {
                if let Some(ref mut indexer) = *self.file_indexer.lock().unwrap() {
                    match indexer.seed_from_spotlight(None) {
                        Ok(count) => {
                            self.status_message = Some(format!("Indexed {} files", count));
                        }
                        Err(e) => {
                            self.status_message = Some(format!("Index failed: {}", e));
                        }
                    }
                }
            }
        });
        
        ui.separator();
        
        // About
        ui.group(|ui| {
            ui.label("Cedar Desktop");
            ui.label("Version: 1.0.0");
            ui.label("Native macOS application");
            ui.hyperlink("https://github.com/yourusername/cedar");
        });
    }
}
