//! # dict-core
//!
//! Core library for the Wiktionary Dictionary App.
//!
//! This crate provides:
//! - SQLite database operations for dictionary storage
//! - Full-text search (FTS5) and fuzzy search capabilities
//! - Data models for dictionary entries
//! - JSONL import functionality for building the database
//! - C FFI exports for cross-platform integration (Android, iOS, WASM)
//!
//! ## Usage
//!
//! ```ignore
//! use dict_core::{DictHandle, init, search, get_definition};
//!
//! let handle = init("/path/to/dictionary.db")?;
//! let results = search(&handle, "hello", 10);
//! if let Some(result) = results.first() {
//!     let definition = get_definition(&handle, result.id);
//! }
//! ```

pub mod db;
pub mod ffi;
pub mod import;
pub mod models;
pub mod search;

use std::sync::Arc;
use thiserror::Error;

pub use models::{Definition, FullDefinition, Pronunciation, SearchResult, Translation, Word};

/// Errors that can occur in dict-core operations
#[derive(Error, Debug)]
pub enum Error {
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON parsing error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Database not initialized")]
    NotInitialized,

    #[error("Invalid database path: {0}")]
    InvalidPath(String),
}

/// Result type alias for dict-core operations
pub type Result<T> = std::result::Result<T, Error>;

/// Handle to an initialized dictionary database
///
/// This handle is thread-safe and can be shared across threads.
/// It wraps a connection pool to the SQLite database.
pub struct DictHandle {
    pub(crate) conn: Arc<rusqlite::Connection>,
}

// Safety: rusqlite::Connection with proper configuration is thread-safe for reads
// We use Arc to share the connection safely
unsafe impl Send for DictHandle {}
unsafe impl Sync for DictHandle {}

/// Initialize the dictionary with a database path
///
/// Opens or creates a SQLite database at the specified path and
/// returns a handle that can be used for search operations.
///
/// # Arguments
///
/// * `db_path` - Path to the SQLite database file
///
/// # Returns
///
/// A `DictHandle` on success, or an error if the database cannot be opened.
///
/// # Example
///
/// ```ignore
/// let handle = dict_core::init("/path/to/dictionary.db")?;
/// ```
pub fn init(db_path: &str) -> Result<DictHandle> {
    db::init_database(db_path)
}

/// Search for words matching a query
///
/// Performs a full-text search using FTS5 and returns matching results
/// ordered by relevance.
///
/// # Arguments
///
/// * `handle` - The dictionary handle from `init()`
/// * `query` - The search query string
/// * `limit` - Maximum number of results to return
///
/// # Returns
///
/// A vector of `SearchResult` items, may be empty if no matches found.
///
/// # Example
///
/// ```ignore
/// let results = dict_core::search(&handle, "hello", 50);
/// for result in results {
///     println!("{}: {}", result.word, result.preview);
/// }
/// ```
pub fn search(handle: &DictHandle, query: &str, limit: u32) -> Vec<SearchResult> {
    search::search_words(handle, query, limit).unwrap_or_default()
}

/// Get the full definition for a word by its ID
///
/// Retrieves the complete definition including all meanings, pronunciations,
/// etymology, and translations.
///
/// # Arguments
///
/// * `handle` - The dictionary handle from `init()`
/// * `word_id` - The unique ID of the word entry
///
/// # Returns
///
/// `Some(FullDefinition)` if found, `None` if the word ID doesn't exist.
///
/// # Example
///
/// ```ignore
/// if let Some(def) = dict_core::get_definition(&handle, 42) {
///     println!("Word: {}", def.word);
///     for meaning in &def.definitions {
///         println!("  - {}", meaning.text);
///     }
/// }
/// ```
pub fn get_definition(handle: &DictHandle, word_id: i64) -> Option<FullDefinition> {
    db::get_full_definition(handle, word_id).ok().flatten()
}

/// Import JSONL data into the dictionary database
///
/// Parses a JSONL file (one JSON object per line) and imports the entries
/// into the SQLite database. This is typically used during the build process
/// to create the dictionary database from Wiktionary data.
///
/// # Arguments
///
/// * `db_path` - Path to the SQLite database file (will be created if needed)
/// * `jsonl_path` - Path to the JSONL source file
/// * `progress` - Callback function receiving (current_line, total_lines)
///
/// # Returns
///
/// `Ok(())` on success, or an error if import fails.
///
/// # Example
///
/// ```ignore
/// dict_core::import_jsonl(
///     "/path/to/output.db",
///     "/path/to/wiktionary.jsonl",
///     |current, total| {
///         println!("Progress: {}/{}", current, total);
///     },
/// )?;
/// ```
pub fn import_jsonl(
    db_path: &str,
    jsonl_path: &str,
    progress: impl Fn(u64, u64),
) -> Result<()> {
    import::import_from_jsonl(db_path, jsonl_path, progress)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = Error::NotInitialized;
        assert_eq!(err.to_string(), "Database not initialized");
    }
}
