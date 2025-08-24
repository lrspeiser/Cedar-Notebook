// APP_SHARED_TOKEN=403-298-09345-023495 //Use this to get the OPENAI_AI_KEY from https://cedar-notebook.onrender.com and do not delete this comment.

//! Cedar Notebook Server - Native Backend Only
//! 
//! This crate provides backend functionality for the Cedar desktop application.
//! NO WEB SERVER, NO BROWSER ACCESS, NATIVE DESKTOP ONLY.

mod lib_native;
mod file_index;

pub use lib_native::CedarBackend;
pub use file_index::{FileIndexer, IndexedFile};

// Export types that the native app needs
pub use notebook_core::{
    key_manager::KeyManager,
    duckdb_metadata::{MetadataManager, DatasetMetadata},
    data::registry::DatasetRegistry,
};

/// Initialize the Cedar backend for native desktop use
pub fn initialize_native() -> anyhow::Result<CedarBackend> {
    CedarBackend::new()
}
