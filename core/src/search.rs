//! Search functionality using FTS5 and fuzzy matching
//!
//! This module provides:
//! - Full-text search using SQLite FTS5
//! - Prefix matching for autocomplete
//! - Fuzzy/approximate string matching using Levenshtein distance

use rusqlite::params;

use crate::models::SearchResult;
use crate::{DictHandle, Result};

/// Maximum Levenshtein distance for fuzzy matches
const MAX_FUZZY_DISTANCE: usize = 2;

/// Minimum query length for fuzzy matching (to avoid too many false positives)
const MIN_FUZZY_QUERY_LENGTH: usize = 3;

/// Search for words matching a query using FTS5
///
/// Returns results ordered by relevance, with exact matches first.
/// The `offset` parameter skips that many results from the beginning of the
/// sorted result set, enabling pagination.
pub fn search_words(handle: &DictHandle, query: &str, limit: u32) -> Result<Vec<SearchResult>> {
    search_words_offset(handle, query, limit, 0)
}

/// Search with offset for pagination.
///
/// Fetches up to `limit` results starting at `offset` in the relevance-sorted list.
pub fn search_words_offset(
    handle: &DictHandle,
    query: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<SearchResult>> {
    let query = query.trim();
    if query.is_empty() {
        return Ok(Vec::new());
    }

    // We need to gather enough results to satisfy offset + limit
    let total_needed = offset.saturating_add(limit);

    // Normalize query for comparison
    let query_lower = query.to_lowercase();

    // Escape special FTS5 characters and prepare query
    let fts_query = prepare_fts_query(query);

    // First try exact match, then prefix match, then FTS match
    let mut results = Vec::new();

    // 1. Exact matches (highest priority, score = 0)
    let exact_results = search_exact(handle, query, total_needed)?;
    for mut result in exact_results {
        result.score = 0.0;
        results.push(result);
    }

    if (results.len() as u32) < total_needed {
        // 2. Prefix matches (score based on length difference)
        let remaining = total_needed - results.len() as u32;
        let prefix_results = search_prefix(handle, query, remaining)?;

        // Add only results not already in the list
        for mut result in prefix_results {
            if !results.iter().any(|r| r.id == result.id) {
                // Score prefix matches by how much longer they are than the query
                let len_diff = result.word.len().saturating_sub(query.len());
                result.score = 1.0 + (len_diff as f64 * 0.1);
                results.push(result);
            }
        }
    }

    if (results.len() as u32) < total_needed {
        // 3. FTS matches (score from FTS5 rank)
        let remaining = total_needed - results.len() as u32;
        let fts_results = search_fts(handle, &fts_query, remaining)?;

        for mut result in fts_results {
            if !results.iter().any(|r| r.id == result.id) {
                // FTS results get a base score of 2.0 plus their rank
                result.score = 2.0 + result.score.abs();
                results.push(result);
            }
        }
    }

    // 4. Fuzzy matches (only if query is long enough and we need more results)
    if (results.len() as u32) < total_needed && query_lower.len() >= MIN_FUZZY_QUERY_LENGTH {
        let remaining = total_needed - results.len() as u32;
        let fuzzy_results = search_fuzzy(handle, &query_lower, remaining)?;

        for result in fuzzy_results {
            if !results.iter().any(|r| r.id == result.id) {
                results.push(result);
            }
        }
    }

    // Sort by score (lower is better)
    results.sort_by(|a, b| {
        a.score
            .partial_cmp(&b.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Apply offset and limit
    let start = std::cmp::min(offset as usize, results.len());
    let end = std::cmp::min(start + limit as usize, results.len());
    let results = results[start..end].to_vec();

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
               COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), ''),
               rank
        FROM words_fts fts
        JOIN words w ON fts.rowid = w.id
        WHERE words_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        "#,
    )?;

    let rows = stmt.query_map(params![query, limit], |row| {
        let id: i64 = row.get(0)?;
        let word: String = row.get(1)?;
        let pos: String = row.get(2)?;
        let definition: String = row.get(3)?;
        let rank: f64 = row.get(4)?;

        let preview = truncate_preview(&definition, 100);

        Ok(SearchResult::with_score(id, word, pos, preview, rank))
    })?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Search for words with fuzzy/approximate matching using Levenshtein distance
///
/// This function retrieves candidate words and filters them by edit distance.
/// For performance, it uses prefix-based candidates when possible.
fn search_fuzzy(handle: &DictHandle, query: &str, limit: u32) -> Result<Vec<SearchResult>> {
    // Get candidates: words that start with the first character(s) of the query
    // This significantly reduces the search space
    let prefix_len = std::cmp::min(2, query.len());
    let prefix = &query[..prefix_len];
    let pattern = format!("{}%", prefix);

    let mut stmt = handle.conn.prepare(
        r#"
        SELECT w.id, w.word, w.pos,
               COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), '')
        FROM words w
        WHERE LOWER(w.word) LIKE LOWER(?)
        LIMIT 1000
        "#,
    )?;

    let candidates = stmt.query_map(params![pattern], row_to_search_result)?;

    // Filter and score by Levenshtein distance
    let mut fuzzy_results: Vec<SearchResult> = candidates
        .filter_map(|r| r.ok())
        .filter_map(|mut result| {
            let word_lower = result.word.to_lowercase();
            let distance = levenshtein_distance(query, &word_lower);

            if distance > 0 && distance <= MAX_FUZZY_DISTANCE {
                // Score is 3.0 (base for fuzzy) + distance
                result.score = 3.0 + distance as f64;
                Some(result)
            } else {
                None
            }
        })
        .collect();

    // Also try candidates that differ by first character (common typos)
    if fuzzy_results.len() < limit as usize && query.len() >= 2 {
        // Get some words that might match with a different first letter
        let suffix = &query[1..];
        let suffix_pattern = format!("_%{}%", suffix);

        let mut stmt2 = handle.conn.prepare(
            r#"
            SELECT w.id, w.word, w.pos,
                   COALESCE((SELECT definition FROM definitions WHERE word_id = w.id LIMIT 1), '')
            FROM words w
            WHERE LOWER(w.word) LIKE LOWER(?)
            LIMIT 500
            "#,
        )?;

        let more_candidates = stmt2.query_map(params![suffix_pattern], row_to_search_result)?;

        for result in more_candidates.filter_map(|r| r.ok()) {
            if fuzzy_results.iter().any(|r| r.id == result.id) {
                continue;
            }

            let word_lower = result.word.to_lowercase();
            let distance = levenshtein_distance(query, &word_lower);

            if distance > 0 && distance <= MAX_FUZZY_DISTANCE {
                let mut result = result;
                result.score = 3.0 + distance as f64;
                fuzzy_results.push(result);
            }
        }
    }

    // Sort by score
    fuzzy_results.sort_by(|a, b| {
        a.score
            .partial_cmp(&b.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    fuzzy_results.truncate(limit as usize);

    Ok(fuzzy_results)
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
        // Find a valid UTF-8 character boundary at or before max_len
        let mut end = max_len;
        while end > 0 && !text.is_char_boundary(end) {
            end -= 1;
        }
        let truncated = &text[..end];

        // Try to truncate at word boundary
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
    let escaped = query.replace('"', "\"\"").replace(['*', '^', ':'], " ");

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
/// The Levenshtein distance is the minimum number of single-character edits
/// (insertions, deletions, or substitutions) required to change one string into another.
///
/// Uses the Wagner-Fischer algorithm with O(min(m,n)) space complexity.
fn levenshtein_distance(a: &str, b: &str) -> usize {
    let a_chars: Vec<char> = a.chars().collect();
    let b_chars: Vec<char> = b.chars().collect();

    let m = a_chars.len();
    let n = b_chars.len();

    // Handle empty strings
    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }

    // Optimize: ensure a is the shorter string for O(min(m,n)) space
    if m > n {
        return levenshtein_distance(b, a);
    }

    // Use two rows instead of full matrix for space efficiency
    let mut prev_row: Vec<usize> = (0..=m).collect();
    let mut curr_row: Vec<usize> = vec![0; m + 1];

    for j in 1..=n {
        curr_row[0] = j;

        for i in 1..=m {
            let cost = if a_chars[i - 1] == b_chars[j - 1] {
                0
            } else {
                1
            };

            curr_row[i] = std::cmp::min(
                std::cmp::min(
                    prev_row[i] + 1,     // deletion
                    curr_row[i - 1] + 1, // insertion
                ),
                prev_row[i - 1] + cost, // substitution
            );
        }

        std::mem::swap(&mut prev_row, &mut curr_row);
    }

    prev_row[m]
}

/// Calculate Damerau-Levenshtein distance (allows transpositions)
///
/// This is similar to Levenshtein but also considers transposition of two
/// adjacent characters as a single edit operation.
#[allow(dead_code)]
fn damerau_levenshtein_distance(a: &str, b: &str) -> usize {
    let a_chars: Vec<char> = a.chars().collect();
    let b_chars: Vec<char> = b.chars().collect();

    let m = a_chars.len();
    let n = b_chars.len();

    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }

    // Need full matrix for transpositions
    let mut d: Vec<Vec<usize>> = vec![vec![0; n + 1]; m + 1];

    for i in 0..=m {
        d[i][0] = i;
    }
    for j in 0..=n {
        d[0][j] = j;
    }

    for i in 1..=m {
        for j in 1..=n {
            let cost = if a_chars[i - 1] == b_chars[j - 1] {
                0
            } else {
                1
            };

            d[i][j] = std::cmp::min(
                std::cmp::min(
                    d[i - 1][j] + 1, // deletion
                    d[i][j - 1] + 1, // insertion
                ),
                d[i - 1][j - 1] + cost, // substitution
            );

            // Transposition
            if i > 1
                && j > 1
                && a_chars[i - 1] == b_chars[j - 2]
                && a_chars[i - 2] == b_chars[j - 1]
            {
                d[i][j] = std::cmp::min(d[i][j], d[i - 2][j - 2] + 1);
            }
        }
    }

    d[m][n]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{init_database, insert_definition, insert_word};

    fn setup_test_db() -> (tempfile::TempDir, DictHandle) {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let handle = init_database(db_path.to_str().unwrap()).unwrap();
        (dir, handle)
    }

    fn populate_test_data(handle: &DictHandle) {
        // Insert test words
        let words = [
            ("hello", "interjection", "A greeting"),
            ("help", "verb", "To assist someone"),
            ("helper", "noun", "One who helps"),
            ("helping", "noun", "A portion of food"),
            ("helicopter", "noun", "An aircraft"),
            ("world", "noun", "The earth"),
            ("word", "noun", "A unit of language"),
            ("work", "verb", "To labor"),
            ("worker", "noun", "One who works"),
            ("test", "noun", "A procedure for testing"),
            ("testing", "verb", "The act of testing"),
        ];

        for (word, pos, definition) in words {
            let word_id = insert_word(&handle.conn, word, pos, "English", "en", 0).unwrap();
            insert_definition(&handle.conn, word_id, definition, &[], &[]).unwrap();
        }
    }

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
    fn test_truncate_preview_multibyte_utf8() {
        // Regression test: truncating in the middle of a multi-byte UTF-8 character
        // should not panic. The subscript characters like ₀ are 3 bytes each.
        let text = "Chemical formula: C₁₅H₂₀O₄ is important";
        // This should not panic even if max_len falls inside a multi-byte char
        let result = truncate_preview(text, 22); // Falls inside ₁
        assert!(result.ends_with("..."));
        assert!(result.len() < text.len());
    }

    #[test]
    fn test_prepare_fts_query_escapes_special_chars() {
        // Special chars should be escaped/removed
        assert_eq!(prepare_fts_query("test*query"), "test* query*");
        assert_eq!(prepare_fts_query("hello:world"), "hello* world*");
    }

    #[test]
    fn test_levenshtein_distance() {
        // Same strings
        assert_eq!(levenshtein_distance("hello", "hello"), 0);

        // Empty strings
        assert_eq!(levenshtein_distance("", "hello"), 5);
        assert_eq!(levenshtein_distance("hello", ""), 5);
        assert_eq!(levenshtein_distance("", ""), 0);

        // One edit
        assert_eq!(levenshtein_distance("hello", "helo"), 1); // deletion
        assert_eq!(levenshtein_distance("hello", "helloo"), 1); // insertion
        assert_eq!(levenshtein_distance("hello", "hallo"), 1); // substitution

        // Two edits
        assert_eq!(levenshtein_distance("hello", "halo"), 2);
        assert_eq!(levenshtein_distance("kitten", "sitten"), 1);
        assert_eq!(levenshtein_distance("kitten", "sittin"), 2);
        assert_eq!(levenshtein_distance("kitten", "sitting"), 3);

        // Completely different
        assert_eq!(levenshtein_distance("abc", "xyz"), 3);
    }

    #[test]
    fn test_damerau_levenshtein_distance() {
        // Transposition
        assert_eq!(damerau_levenshtein_distance("ab", "ba"), 1);
        assert_eq!(damerau_levenshtein_distance("hello", "hlelo"), 1);

        // Compare with standard Levenshtein (which counts transposition as 2)
        assert_eq!(levenshtein_distance("ab", "ba"), 2);
    }

    #[test]
    fn test_search_exact_match() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "hello", 10).unwrap();
        assert!(!results.is_empty());
        assert_eq!(results[0].word, "hello");
        assert_eq!(results[0].score, 0.0); // Exact match
    }

    #[test]
    fn test_search_prefix_match() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "hel", 10).unwrap();
        assert!(results.len() >= 4); // hello, help, helper, helping

        // Results should be sorted by relevance
        // Shorter matches should come first
        let words: Vec<&str> = results.iter().map(|r| r.word.as_str()).collect();
        assert!(words.contains(&"help"));
        assert!(words.contains(&"hello"));
    }

    #[test]
    fn test_search_empty_query() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "", 10).unwrap();
        assert!(results.is_empty());

        let results = search_words(&handle, "   ", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_search_limit() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "h", 3).unwrap();
        assert!(results.len() <= 3);
    }

    #[test]
    fn test_search_no_duplicates() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "help", 10).unwrap();

        // Check for duplicates
        let ids: Vec<i64> = results.iter().map(|r| r.id).collect();
        let unique_ids: std::collections::HashSet<i64> = ids.iter().copied().collect();
        assert_eq!(
            ids.len(),
            unique_ids.len(),
            "Search results contain duplicates"
        );
    }

    #[test]
    fn test_search_results_sorted_by_score() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        let results = search_words(&handle, "help", 10).unwrap();

        // Verify results are sorted by score (ascending)
        for i in 1..results.len() {
            assert!(
                results[i].score >= results[i - 1].score,
                "Results not sorted by score: {} vs {}",
                results[i - 1].score,
                results[i].score
            );
        }
    }

    #[test]
    fn test_fuzzy_search_typo_tolerance() {
        let (_dir, handle) = setup_test_db();
        populate_test_data(&handle);

        // Common typo: "helo" instead of "hello"
        let results = search_words(&handle, "helo", 10).unwrap();
        let words: Vec<&str> = results.iter().map(|r| r.word.as_str()).collect();

        // Should find "hello" with fuzzy matching
        assert!(
            words.contains(&"hello"),
            "Expected to find 'hello' for query 'helo'"
        );
    }
}
