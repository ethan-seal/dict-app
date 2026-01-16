//! Search functionality using FTS5 and fuzzy matching
//!
//! This module provides:
//! - Full-text search using SQLite FTS5
//! - Prefix matching for autocomplete
//! - Fuzzy/approximate string matching (TODO)

use rusqlite::params;

use crate::models::SearchResult;
use crate::{DictHandle, Result};

/// Search for words matching a query using FTS5
///
/// Returns results ordered by relevance, with exact matches first.
pub fn search_words(handle: &DictHandle, query: &str, limit: u32) -> Result<Vec<SearchResult>> {
    let query = query.trim();
    if query.is_empty() {
        return Ok(Vec::new());
    }

    // Escape special FTS5 characters and prepare query
    let fts_query = prepare_fts_query(query);

    // First try exact match, then prefix match, then FTS match
    let mut results = Vec::new();

    // 1. Exact matches (highest priority)
    results.extend(search_exact(handle, query, limit)?);

    if (results.len() as u32) < limit {
        // 2. Prefix matches
        let remaining = limit - results.len() as u32;
        let prefix_results = search_prefix(handle, query, remaining)?;
        
        // Add only results not already in the list
        for result in prefix_results {
            if !results.iter().any(|r| r.id == result.id) {
                results.push(result);
            }
        }
    }

    if (results.len() as u32) < limit {
        // 3. FTS matches
        let remaining = limit - results.len() as u32;
        let fts_results = search_fts(handle, &fts_query, remaining)?;
        
        for result in fts_results {
            if !results.iter().any(|r| r.id == result.id) {
                results.push(result);
            }
        }
    }

    // TODO: Add fuzzy matching for typo tolerance
    // This could use techniques like:
    // - Levenshtein distance
    // - Trigram similarity
    // - Soundex/Metaphone phonetic matching

    Ok(results)
}

/// Search for exact word matches
fn search_exact(handle: &DictHandle, word: &str, limit: u32) -> Result<Vec<SearchResult>> {
    let mut stmt = handle.conn.prepare(
        r#"
        SELECT w.id, w.word, w.pos, 
               COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), '')
        FROM words w
        WHERE w.word = ?
        LIMIT ?
        "#,
    )?;

    let rows = stmt.query_map(params![word, limit], row_to_search_result)?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Search for words starting with a prefix
fn search_prefix(handle: &DictHandle, prefix: &str, limit: u32) -> Result<Vec<SearchResult>> {
    let pattern = format!("{}%", prefix);
    
    let mut stmt = handle.conn.prepare(
        r#"
        SELECT w.id, w.word, w.pos,
               COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), '')
        FROM words w
        WHERE w.word LIKE ?
        ORDER BY length(w.word), w.word
        LIMIT ?
        "#,
    )?;

    let rows = stmt.query_map(params![pattern, limit], row_to_search_result)?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Search using FTS5 full-text search
fn search_fts(handle: &DictHandle, query: &str, limit: u32) -> Result<Vec<SearchResult>> {
    let mut stmt = handle.conn.prepare(
        r#"
        SELECT w.id, w.word, w.pos,
               COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), '')
        FROM words_fts fts
        JOIN words w ON fts.rowid = w.id
        WHERE words_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        "#,
    )?;

    let rows = stmt.query_map(params![query, limit], row_to_search_result)?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Convert a database row to a SearchResult
fn row_to_search_result(row: &rusqlite::Row) -> rusqlite::Result<SearchResult> {
    let id: i64 = row.get(0)?;
    let word: String = row.get(1)?;
    let pos: String = row.get(2)?;
    let definition: String = row.get(3)?;
    
    // Truncate preview to reasonable length
    let preview = truncate_preview(&definition, 100);
    
    Ok(SearchResult::new(id, word, pos, preview))
}

/// Truncate definition text for preview
fn truncate_preview(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        // Try to truncate at word boundary
        let truncated = &text[..max_len];
        if let Some(last_space) = truncated.rfind(' ') {
            format!("{}...", &truncated[..last_space])
        } else {
            format!("{}...", truncated)
        }
    }
}

/// Prepare a search query for FTS5
///
/// Escapes special characters and converts to prefix search format.
fn prepare_fts_query(query: &str) -> String {
    // Escape FTS5 special characters: " * ^ :
    let escaped = query
        .replace('"', "\"\"")
        .replace('*', " ")
        .replace('^', " ")
        .replace(':', " ");
    
    // Add prefix matching by appending *
    // This allows "hel" to match "hello"
    let words: Vec<&str> = escaped.split_whitespace().collect();
    if words.is_empty() {
        return String::new();
    }
    
    // Make each word a prefix search
    words
        .iter()
        .map(|w| format!("{}*", w))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Calculate Levenshtein distance between two strings
///
/// TODO: Implement for fuzzy matching
#[allow(dead_code)]
fn levenshtein_distance(a: &str, b: &str) -> usize {
    // TODO: Implement Levenshtein distance algorithm
    // This will be used for typo tolerance in search
    
    // Placeholder: return 0 for equal strings, 1 otherwise
    if a == b { 0 } else { 1 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prepare_fts_query() {
        assert_eq!(prepare_fts_query("hello"), "hello*");
        assert_eq!(prepare_fts_query("hello world"), "hello* world*");
        assert_eq!(prepare_fts_query(""), "");
    }

    #[test]
    fn test_truncate_preview() {
        assert_eq!(truncate_preview("short", 100), "short");
        assert_eq!(
            truncate_preview("this is a very long text that should be truncated", 20),
            "this is a very long..."
        );
    }

    #[test]
    fn test_prepare_fts_query_escapes_special_chars() {
        // Special chars should be escaped/removed
        assert_eq!(prepare_fts_query("test*query"), "test* query*");
        assert_eq!(prepare_fts_query("hello:world"), "hello* world*");
    }
}
