//! SQLite database operations
//!
//! This module handles all database interactions including:
//! - Database initialization and schema creation
//! - Word and definition queries
//! - FTS5 index management

use std::sync::Arc;

use rusqlite::{params, Connection, OpenFlags};

use crate::models::{Definition, FullDefinition, Pronunciation, Translation};
use crate::{DictHandle, Result};

/// SQL schema for the dictionary database
const SCHEMA: &str = r#"
-- Main word entries
CREATE TABLE IF NOT EXISTS words (
    id INTEGER PRIMARY KEY,
    word TEXT NOT NULL,
    pos TEXT NOT NULL,
    language TEXT NOT NULL,
    etymology_num INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_words_word ON words(word);
CREATE INDEX IF NOT EXISTS idx_words_language ON words(language);

-- Full-text search using FTS5
CREATE VIRTUAL TABLE IF NOT EXISTS words_fts USING fts5(
    word,
    content='words',
    content_rowid='id'
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS words_ai AFTER INSERT ON words BEGIN
    INSERT INTO words_fts(rowid, word) VALUES (new.id, new.word);
END;

CREATE TRIGGER IF NOT EXISTS words_ad AFTER DELETE ON words BEGIN
    INSERT INTO words_fts(words_fts, rowid, word) VALUES('delete', old.id, old.word);
END;

CREATE TRIGGER IF NOT EXISTS words_au AFTER UPDATE ON words BEGIN
    INSERT INTO words_fts(words_fts, rowid, word) VALUES('delete', old.id, old.word);
    INSERT INTO words_fts(rowid, word) VALUES (new.id, new.word);
END;

-- Definitions (one word can have many)
CREATE TABLE IF NOT EXISTS definitions (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    definition TEXT NOT NULL,
    examples TEXT,  -- JSON array
    tags TEXT,      -- JSON array
    FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_definitions_word_id ON definitions(word_id);

-- Pronunciations
CREATE TABLE IF NOT EXISTS pronunciations (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    ipa TEXT,
    audio_url TEXT,
    accent TEXT,
    FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_pronunciations_word_id ON pronunciations(word_id);

-- Etymology
CREATE TABLE IF NOT EXISTS etymologies (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    etymology_text TEXT NOT NULL,
    FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_etymologies_word_id ON etymologies(word_id);

-- Translations
CREATE TABLE IF NOT EXISTS translations (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    target_language TEXT NOT NULL,
    translation TEXT NOT NULL,
    FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_translations_word_id ON translations(word_id);
CREATE INDEX IF NOT EXISTS idx_translations_language ON translations(target_language);
"#;

/// Initialize the dictionary database
///
/// Opens the database at the specified path, creating it if necessary,
/// and ensures the schema is set up correctly.
pub fn init_database(db_path: &str) -> Result<DictHandle> {
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_WRITE
            | OpenFlags::SQLITE_OPEN_CREATE
            | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;

    // Enable foreign keys
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;

    // Apply schema
    conn.execute_batch(SCHEMA)?;

    Ok(DictHandle {
        conn: Arc::new(conn),
    })
}

/// Open an existing database in read-only mode
///
/// Used for search operations where no writes are needed.
pub fn open_readonly(db_path: &str) -> Result<DictHandle> {
    let conn = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;

    Ok(DictHandle {
        conn: Arc::new(conn),
    })
}

/// Get the full definition for a word by ID
pub fn get_full_definition(handle: &DictHandle, word_id: i64) -> Result<Option<FullDefinition>> {
    // Get basic word info
    let mut stmt = handle.conn.prepare(
        "SELECT word, pos, language FROM words WHERE id = ?",
    )?;

    let word_row = stmt.query_row(params![word_id], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    });

    let (word, pos, language) = match word_row {
        Ok(row) => row,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(None),
        Err(e) => return Err(e.into()),
    };

    let mut full_def = FullDefinition::new(word, pos, language);

    // Get definitions
    full_def.definitions = get_definitions(handle, word_id)?;

    // Get pronunciations
    full_def.pronunciations = get_pronunciations(handle, word_id)?;

    // Get etymology
    full_def.etymology = get_etymology(handle, word_id)?;

    // Get translations
    full_def.translations = get_translations(handle, word_id)?;

    Ok(Some(full_def))
}

/// Get all definitions for a word
fn get_definitions(handle: &DictHandle, word_id: i64) -> Result<Vec<Definition>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, definition, examples, tags FROM definitions WHERE word_id = ?",
    )?;

    let rows = stmt.query_map(params![word_id], |row| {
        let id: i64 = row.get(0)?;
        let text: String = row.get(1)?;
        let examples_json: Option<String> = row.get(2)?;
        let tags_json: Option<String> = row.get(3)?;

        // Parse JSON arrays
        let examples: Vec<String> = examples_json
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        let tags: Vec<String> = tags_json
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();

        Ok(Definition {
            id,
            text,
            examples,
            tags,
        })
    })?;

    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Get all pronunciations for a word
fn get_pronunciations(handle: &DictHandle, word_id: i64) -> Result<Vec<Pronunciation>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, ipa, audio_url, accent FROM pronunciations WHERE word_id = ?",
    )?;

    let rows = stmt.query_map(params![word_id], |row| {
        Ok(Pronunciation {
            id: row.get(0)?,
            ipa: row.get(1)?,
            audio_url: row.get(2)?,
            accent: row.get(3)?,
        })
    })?;

    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Get etymology for a word
fn get_etymology(handle: &DictHandle, word_id: i64) -> Result<Option<String>> {
    let mut stmt = handle.conn.prepare(
        "SELECT etymology_text FROM etymologies WHERE word_id = ? LIMIT 1",
    )?;

    match stmt.query_row(params![word_id], |row| row.get(0)) {
        Ok(text) => Ok(Some(text)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Get all translations for a word
fn get_translations(handle: &DictHandle, word_id: i64) -> Result<Vec<Translation>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, target_language, translation FROM translations WHERE word_id = ?",
    )?;

    let rows = stmt.query_map(params![word_id], |row| {
        Ok(Translation {
            id: row.get(0)?,
            target_language: row.get(1)?,
            translation: row.get(2)?,
        })
    })?;

    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Insert a word entry and return its ID
pub fn insert_word(
    conn: &Connection,
    word: &str,
    pos: &str,
    language: &str,
    etymology_num: i32,
) -> Result<i64> {
    conn.execute(
        "INSERT INTO words (word, pos, language, etymology_num) VALUES (?, ?, ?, ?)",
        params![word, pos, language, etymology_num],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Insert a definition for a word
pub fn insert_definition(
    conn: &Connection,
    word_id: i64,
    definition: &str,
    examples: &[String],
    tags: &[String],
) -> Result<i64> {
    let examples_json = serde_json::to_string(examples)?;
    let tags_json = serde_json::to_string(tags)?;

    conn.execute(
        "INSERT INTO definitions (word_id, definition, examples, tags) VALUES (?, ?, ?, ?)",
        params![word_id, definition, examples_json, tags_json],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Insert a pronunciation for a word
pub fn insert_pronunciation(
    conn: &Connection,
    word_id: i64,
    ipa: Option<&str>,
    audio_url: Option<&str>,
    accent: Option<&str>,
) -> Result<i64> {
    conn.execute(
        "INSERT INTO pronunciations (word_id, ipa, audio_url, accent) VALUES (?, ?, ?, ?)",
        params![word_id, ipa, audio_url, accent],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Insert an etymology for a word
pub fn insert_etymology(conn: &Connection, word_id: i64, text: &str) -> Result<i64> {
    conn.execute(
        "INSERT INTO etymologies (word_id, etymology_text) VALUES (?, ?)",
        params![word_id, text],
    )?;
    Ok(conn.last_insert_rowid())
}

/// Insert a translation for a word
pub fn insert_translation(
    conn: &Connection,
    word_id: i64,
    target_language: &str,
    translation: &str,
) -> Result<i64> {
    conn.execute(
        "INSERT INTO translations (word_id, target_language, translation) VALUES (?, ?, ?)",
        params![word_id, target_language, translation],
    )?;
    Ok(conn.last_insert_rowid())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_init_database() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let handle = init_database(db_path.to_str().unwrap()).unwrap();
        
        // Verify tables exist
        let count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='words'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn test_insert_and_get_definition() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let handle = init_database(db_path.to_str().unwrap()).unwrap();

        // Insert a word
        let word_id = insert_word(&handle.conn, "test", "noun", "English", 0).unwrap();
        
        // Insert a definition
        insert_definition(
            &handle.conn,
            word_id,
            "A procedure for testing",
            &["This is a test.".to_string()],
            &["formal".to_string()],
        )
        .unwrap();

        // Retrieve and verify
        let full_def = get_full_definition(&handle, word_id).unwrap().unwrap();
        assert_eq!(full_def.word, "test");
        assert_eq!(full_def.pos, "noun");
        assert_eq!(full_def.definitions.len(), 1);
        assert_eq!(full_def.definitions[0].text, "A procedure for testing");
    }
}
