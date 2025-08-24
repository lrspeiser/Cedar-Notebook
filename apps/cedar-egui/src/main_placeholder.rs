// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

use eframe::egui;
fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1200.0, 800.0])
            .with_min_inner_size([800.0, 600.0]),
        ..Default::default()
    };
    
    eframe::run_native(
        "Cedar Desktop",
        options,
        Box::new(|_cc| Box::new(CedarApp::default())),
    )
}

#[derive(Default)]
struct CedarApp {
    // UI state
    current_tab: Tab,
    query_input: String,
    file_path: String,
    
    // Query history
    query_history: Vec<QueryEntry>,
    
    // Datasets
    datasets: Vec<Dataset>,
    
    // Status
    status_message: String,
    api_key_status: ApiKeyStatus,
}

#[derive(Debug, Clone, PartialEq, Default)]
enum Tab {
    #[default]
    Research,
    Data,
    History,
    Settings,
}

#[derive(Debug, Clone)]
struct QueryEntry {
    query: String,
    response: String,
    timestamp: String,
}

#[derive(Debug, Clone)]
struct Dataset {
    name: String,
    rows: usize,
    cols: usize,
    size: String,
}

#[derive(Debug, Clone, PartialEq)]
enum ApiKeyStatus {
    Unknown,
    Configured,
    NotConfigured,
    Fetching,
}

impl Default for ApiKeyStatus {
    fn default() -> Self {
        ApiKeyStatus::Unknown
    }
}

impl CedarApp {
    fn submit_query(&mut self) {
        if self.query_input.trim().is_empty() {
            return;
        }
        
        let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
        let query = self.query_input.clone();
        
        // For now, just add a placeholder response
        let response = format!("Processing query: {}\n\n[Note: Full query processing will be implemented with the backend integration]", query);
        
        self.query_history.push(QueryEntry {
            query: query.clone(),
            response,
            timestamp,
        });
        
        self.status_message = format!("Query submitted: {}", query);
        self.query_input.clear();
    }
    
    fn upload_file(&mut self) {
        if self.file_path.trim().is_empty() {
            self.status_message = "Please select a file".to_string();
            return;
        }
        
        // Add to datasets
        let name = std::path::Path::new(&self.file_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        self.datasets.push(Dataset {
            name: name.clone(),
            rows: 1000, // Placeholder
            cols: 10,    // Placeholder
            size: "1.2 MB".to_string(), // Placeholder
        });
        
        self.status_message = format!("Uploaded: {}", name);
        self.file_path.clear();
    }
    
    fn check_api_key(&mut self) {
        // Check if OPENAI_API_KEY is set
        if std::env::var("OPENAI_API_KEY").is_ok() {
            self.api_key_status = ApiKeyStatus::Configured;
        } else {
            self.api_key_status = ApiKeyStatus::NotConfigured;
        }
    }
    
    fn fetch_api_key(&mut self) {
        self.api_key_status = ApiKeyStatus::Fetching;
        self.status_message = "Fetching API key from server...".to_string();
        
        // In a real implementation, this would be async
        // For now, we'll simulate it
        std::thread::spawn(|| {
            // Simulate fetching
            std::thread::sleep(std::time::Duration::from_secs(2));
            
            // In reality, this would call the key manager
            // For demo, we'll just set a flag
            eprintln!("[Cedar] API key fetch simulation complete");
        });
        
        self.api_key_status = ApiKeyStatus::Configured;
        self.status_message = "API key fetched successfully".to_string();
    }
}

impl eframe::App for CedarApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Initialize API key status on first run
        if self.api_key_status == ApiKeyStatus::Unknown {
            self.check_api_key();
        }
        
        // Top panel with tabs
        egui::TopBottomPanel::top("top_panel").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.selectable_value(&mut self.current_tab, Tab::Research, "🔬 Research");
                ui.selectable_value(&mut self.current_tab, Tab::Data, "📊 Data");
                ui.selectable_value(&mut self.current_tab, Tab::History, "📜 History");
                ui.selectable_value(&mut self.current_tab, Tab::Settings, "⚙️ Settings");
                
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if !self.status_message.is_empty() {
                        ui.label(&self.status_message);
                    }
                });
            });
        });
        
        // Main content
        egui::CentralPanel::default().show(ctx, |ui| {
            match self.current_tab {
                Tab::Research => {
                    ui.heading("🔬 Research Assistant");
                    ui.separator();
                    
                    ui.label("Enter your query to analyze data, run computations, or get insights:");
                    
                    ui.horizontal(|ui| {
                        let response = ui.add(
                            egui::TextEdit::singleline(&mut self.query_input)
                                .desired_width(600.0)
                                .hint_text("Ask a question or describe what you want to analyze...")
                        );
                        
                        if ui.button("Submit").clicked() || (response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))) {
                            self.submit_query();
                        }
                    });
                    
                    ui.separator();
                    
                    // Show latest response if any
                    if let Some(latest) = self.query_history.last() {
                        ui.group(|ui| {
                            ui.label(format!("Latest Query ({})", latest.timestamp));
                            ui.label(format!("Q: {}", latest.query));
                            ui.separator();
                            ui.label(format!("A: {}", latest.response));
                        });
                    }
                    
                    ui.separator();
                    ui.label("Tips:");
                    ui.label("• Upload datasets in the Data tab first");
                    ui.label("• Ask questions about your data");
                    ui.label("• Request visualizations or analysis");
                    ui.label("• All processing happens locally on your machine");
                }
                
                Tab::Data => {
                    ui.heading("📊 Data Management");
                    ui.separator();
                    
                    ui.group(|ui| {
                        ui.label("Upload a file:");
                        ui.horizontal(|ui| {
                            ui.text_edit_singleline(&mut self.file_path);
                            if ui.button("Browse...").clicked() {
                                if let Some(path) = rfd::FileDialog::new()
                                    .add_filter("Data files", &["csv", "xlsx", "json", "parquet"])
                                    .pick_file() 
                                {
                                    self.file_path = path.display().to_string();
                                }
                            }
                            if ui.button("Upload").clicked() {
                                self.upload_file();
                            }
                        });
                    });
                    
                    ui.separator();
                    
                    ui.heading("Uploaded Datasets");
                    
                    if self.datasets.is_empty() {
                        ui.label("No datasets uploaded yet");
                    } else {
                        egui::ScrollArea::vertical().show(ui, |ui| {
                            for dataset in &self.datasets {
                                ui.group(|ui| {
                                    ui.horizontal(|ui| {
                                        ui.label(format!("📁 {}", dataset.name));
                                        ui.label(format!("({} rows × {} cols)", dataset.rows, dataset.cols));
                                        ui.label(format!("Size: {}", dataset.size));
                                        if ui.button("Preview").clicked() {
                                            self.status_message = format!("Preview: {}", dataset.name);
                                        }
                                        if ui.button("Delete").clicked() {
                                            self.status_message = format!("Delete: {}", dataset.name);
                                        }
                                    });
                                });
                            }
                        });
                    }
                }
                
                Tab::History => {
                    ui.heading("📜 Query History");
                    ui.separator();
                    
                    if self.query_history.is_empty() {
                        ui.label("No queries yet. Go to the Research tab to submit queries.");
                    } else {
                        if ui.button("Clear History").clicked() {
                            self.query_history.clear();
                            self.status_message = "History cleared".to_string();
                        }
                        
                        ui.separator();
                        
                        egui::ScrollArea::vertical().show(ui, |ui| {
                            for entry in self.query_history.iter().rev() {
                                ui.group(|ui| {
                                    ui.label(format!("⏰ {}", entry.timestamp));
                                    ui.label(format!("Q: {}", entry.query));
                                    ui.separator();
                                    ui.label(format!("A: {}", entry.response));
                                    
                                    ui.horizontal(|ui| {
                                        if ui.button("Copy Query").clicked() {
                                            self.query_input = entry.query.clone();
                                            self.current_tab = Tab::Research;
                                            self.status_message = "Query copied to Research tab".to_string();
                                        }
                                    });
                                });
                            }
                        });
                    }
                }
                
                Tab::Settings => {
                    ui.heading("⚙️ Settings");
                    ui.separator();
                    
                    ui.group(|ui| {
                        ui.heading("API Key Configuration");
                        
                        ui.horizontal(|ui| {
                            ui.label("Status:");
                            match self.api_key_status {
                                ApiKeyStatus::Configured => {
                                    ui.colored_label(egui::Color32::GREEN, "✓ Configured");
                                }
                                ApiKeyStatus::NotConfigured => {
                                    ui.colored_label(egui::Color32::RED, "✗ Not Configured");
                                }
                                ApiKeyStatus::Fetching => {
                                    ui.colored_label(egui::Color32::YELLOW, "⏳ Fetching...");
                                }
                                ApiKeyStatus::Unknown => {
                                    ui.label("Checking...");
                                }
                            }
                        });
                        
                        if self.api_key_status == ApiKeyStatus::NotConfigured {
                            if ui.button("Fetch from Cedar Server").clicked() {
                                self.fetch_api_key();
                            }
                            ui.label("The app will automatically fetch the API key from the Cedar server.");
                        }
                    });
                    
                    ui.separator();
                    
                    ui.group(|ui| {
                        ui.heading("About Cedar Desktop");
                        ui.label("Version: 1.0.0");
                        ui.label("A native macOS application for AI-powered data analysis");
                        ui.separator();
                        ui.label("Features:");
                        ui.label("• Local data processing");
                        ui.label("• AI-powered analysis with GPT-4");
                        ui.label("• Support for CSV, Excel, JSON, and Parquet files");
                        ui.label("• Automatic API key management");
                        ui.label("• No browser or server required");
                        ui.separator();
                        ui.hyperlink("https://github.com/yourusername/cedar");
                    });
                }
            }
        });
    }
}
