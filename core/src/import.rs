//! JSONL import functionality
//!
//! This module handles importing dictionary data from JSONL files
//! (as exported from Wiktionary via kaikki.org) into the SQLite database.
//!
//! Supports both raw JSONL and gzip-compressed JSONL files (.jsonl.gz).

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use flate2::read::GzDecoder;
use rusqlite::Connection;

use crate::db::{
    insert_definition, insert_etymology, insert_pronunciation, insert_translation, insert_word,
};
use crate::models::{RawSound, RawWordEntry};
use crate::Result;

/// Import statistics returned after processing
#[derive(Debug, Clone, Default)]
pub struct ImportStats {
    /// Total number of lines processed
    pub lines_processed: u64,
    /// Number of words successfully imported
    pub words_imported: u64,
    /// Number of definitions imported
    pub definitions_imported: u64,
    /// Number of pronunciations imported
    pub pronunciations_imported: u64,
    /// Number of etymologies imported
    pub etymologies_imported: u64,
    /// Number of translations imported
    pub translations_imported: u64,
    /// Number of errors encountered
    pub errors: u64,
    /// Number of skipped entries (e.g., empty lines)
    pub skipped: u64,
}

/// Import dictionary data from a JSONL file
///
/// Each line in the JSONL file should be a valid JSON object representing
/// a word entry in the Wiktionary format.
///
/// Supports both raw JSONL and gzip-compressed files (.jsonl.gz).
///
/// # Arguments
///
/// * `db_path` - Path to the SQLite database (will be created if needed)
/// * `jsonl_path` - Path to the source JSONL file (can be .jsonl or .jsonl.gz)
/// * `progress` - Callback function receiving (current_line, total_lines)
pub fn import_from_jsonl(
    db_path: &str,
    jsonl_path: &str,
    progress: impl Fn(u64, u64),
) -> Result<()> {
    import_from_jsonl_with_stats(db_path, jsonl_path, progress).map(|_| ())
}

/// Import dictionary data from a JSONL file and return statistics
///
/// Same as `import_from_jsonl` but returns detailed import statistics.
pub fn import_from_jsonl_with_stats(
    db_path: &str,
    jsonl_path: &str,
    progress: impl Fn(u64, u64),
) -> Result<ImportStats> {
    let path = Path::new(jsonl_path);
    let is_gzipped = path
        .extension()
        .map(|ext| ext == "gz")
        .unwrap_or(false);

    // Count total lines for progress reporting
    let total_lines = if is_gzipped {
        count_lines_gzipped(jsonl_path)?
    } else {
        count_lines(jsonl_path)?
    };

    // Open database with write access
    let conn = Connection::open(db_path)?;

    // Configure for bulk import
    configure_for_import(&conn)?;

    // Create schema if needed
    conn.execute_batch(include_str!("../sql/schema.sql").trim_start_matches('\u{feff}'))?;

    // Open JSONL file (handle gzip)
    let file = File::open(jsonl_path)?;
    let reader: Box<dyn BufRead> = if is_gzipped {
        Box::new(BufReader::new(GzDecoder::new(file)))
    } else {
        Box::new(BufReader::new(file))
    };

    // Begin transaction for better performance
    conn.execute_batch("BEGIN TRANSACTION")?;

    let mut stats = ImportStats::default();

    for line_result in reader.lines() {
        stats.lines_processed += 1;

        // Report progress periodically
        if stats.lines_processed % 1000 == 0 {
            progress(stats.lines_processed, total_lines);
        }

        let line = match line_result {
            Ok(l) => l,
            Err(_) => {
                stats.errors += 1;
                continue;
            }
        };

        // Skip empty lines
        if line.trim().is_empty() {
            stats.skipped += 1;
            continue;
        }

        // Parse JSON
        let entry: RawWordEntry = match serde_json::from_str(&line) {
            Ok(e) => e,
            Err(e) => {
                log::debug!("JSON parse error at line {}: {}", stats.lines_processed, e);
                stats.errors += 1;
                continue;
            }
        };

        // Import the entry
        match import_entry_with_stats(&conn, &entry) {
            Ok(entry_stats) => {
                stats.words_imported += 1;
                stats.definitions_imported += entry_stats.definitions;
                stats.pronunciations_imported += entry_stats.pronunciations;
                stats.etymologies_imported += entry_stats.etymologies;
                stats.translations_imported += entry_stats.translations;
            }
            Err(e) => {
                log::debug!("Import error at line {}: {}", stats.lines_processed, e);
                stats.errors += 1;
            }
        }

        // Commit periodically to avoid huge transactions
        if stats.lines_processed % 10000 == 0 {
            conn.execute_batch("COMMIT; BEGIN TRANSACTION")?;
        }
    }

    // Final commit
    conn.execute_batch("COMMIT")?;

    // Final progress update
    progress(stats.lines_processed, total_lines);

    // Log import statistics
    log::info!(
        "Import complete: {} lines, {} words, {} definitions, {} errors",
        stats.lines_processed,
        stats.words_imported,
        stats.definitions_imported,
        stats.errors
    );

    Ok(stats)
}

/// Count the number of lines in a file
fn count_lines(path: &str) -> Result<u64> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    Ok(reader.lines().count() as u64)
}

/// Count the number of lines in a gzipped file
fn count_lines_gzipped(path: &str) -> Result<u64> {
    let file = File::open(path)?;
    let decoder = GzDecoder::new(file);
    let reader = BufReader::new(decoder);
    Ok(reader.lines().count() as u64)
}

/// Configure SQLite connection for fast bulk imports
fn configure_for_import(conn: &Connection) -> Result<()> {
    // These settings trade durability for speed during import
    // The database should be rebuilt from source if corrupted
    conn.execute_batch(
        r#"
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA cache_size = -64000;  -- 64MB cache
        PRAGMA temp_store = MEMORY;
        "#,
    )?;
    Ok(())
}

/// Statistics from importing a single entry
struct EntryStats {
    definitions: u64,
    pronunciations: u64,
    etymologies: u64,
    translations: u64,
}

/// Import a single word entry into the database and return stats
fn import_entry_with_stats(conn: &Connection, entry: &RawWordEntry) -> Result<EntryStats> {
    let mut stats = EntryStats {
        definitions: 0,
        pronunciations: 0,
        etymologies: 0,
        translations: 0,
    };

    // Insert the word
    let etymology_num = entry.etymology_number.unwrap_or(0);
    let word_id = insert_word(conn, &entry.word, &entry.pos, &entry.lang, etymology_num)?;

    // Insert definitions from senses
    for sense in &entry.senses {
        // Get the definition text (prefer glosses over raw_glosses)
        let definition_text = sense
            .glosses
            .first()
            .or_else(|| sense.raw_glosses.first())
            .map(|s| s.as_str())
            .unwrap_or("");

        if definition_text.is_empty() {
            continue;
        }

        // Collect examples
        let examples: Vec<String> = sense.examples.iter().map(|e| e.text.clone()).collect();

        insert_definition(conn, word_id, definition_text, &examples, &sense.tags)?;
        stats.definitions += 1;
    }

    // Insert pronunciations
    for sound in &entry.sounds {
        if let Some(ipa) = &sound.ipa {
            let audio_url = get_audio_url(sound);
            let accent = sound.tags.first().map(|s| s.as_str());
            insert_pronunciation(conn, word_id, Some(ipa), audio_url.as_deref(), accent)?;
            stats.pronunciations += 1;
        }
    }

    // Insert etymology
    if let Some(etymology_text) = &entry.etymology_text {
        if !etymology_text.is_empty() {
            insert_etymology(conn, word_id, etymology_text)?;
            stats.etymologies += 1;
        }
    }

    // Insert translations
    for translation in &entry.translations {
        if !translation.word.is_empty() {
            let lang = if translation.code.is_empty() {
                &translation.lang
            } else {
                &translation.code
            };
            insert_translation(conn, word_id, lang, &translation.word)?;
            stats.translations += 1;
        }
    }

    Ok(stats)
}

/// Get the best audio URL from a sound entry
fn get_audio_url(sound: &RawSound) -> Option<String> {
    // Prefer OGG, then MP3, then generic audio
    sound
        .ogg_url
        .clone()
        .or_else(|| sound.mp3_url.clone())
        .or_else(|| sound.audio.clone())
}

/// Create the schema SQL file directory structure
/// 
/// Note: The schema is embedded at compile time. This function creates
/// the directory for development purposes.
pub fn ensure_schema_dir() -> std::io::Result<()> {
    let schema_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("sql");
    std::fs::create_dir_all(schema_dir)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_audio_url_prefers_ogg() {
        let sound = RawSound {
            ipa: Some("test".to_string()),
            audio: Some("audio.mp3".to_string()),
            ogg_url: Some("audio.ogg".to_string()),
            mp3_url: Some("audio.mp3".to_string()),
            tags: vec![],
        };
        assert_eq!(get_audio_url(&sound), Some("audio.ogg".to_string()));
    }

    #[test]
    fn test_get_audio_url_fallback_to_mp3() {
        let sound = RawSound {
            ipa: Some("test".to_string()),
            audio: None,
            ogg_url: None,
            mp3_url: Some("audio.mp3".to_string()),
            tags: vec![],
        };
        assert_eq!(get_audio_url(&sound), Some("audio.mp3".to_string()));
    }
}
