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

// ============================================================================
// Update Operations
// ============================================================================

/// Update a word entry
pub fn update_word(
    conn: &Connection,
    word_id: i64,
    word: &str,
    pos: &str,
    language: &str,
) -> Result<bool> {
    let rows = conn.execute(
        "UPDATE words SET word = ?, pos = ?, language = ? WHERE id = ?",
        params![word, pos, language, word_id],
    )?;
    Ok(rows > 0)
}

/// Update a definition
pub fn update_definition(
    conn: &Connection,
    definition_id: i64,
    definition: &str,
    examples: &[String],
    tags: &[String],
) -> Result<bool> {
    let examples_json = serde_json::to_string(examples)?;
    let tags_json = serde_json::to_string(tags)?;

    let rows = conn.execute(
        "UPDATE definitions SET definition = ?, examples = ?, tags = ? WHERE id = ?",
        params![definition, examples_json, tags_json, definition_id],
    )?;
    Ok(rows > 0)
}

/// Update a pronunciation
pub fn update_pronunciation(
    conn: &Connection,
    pronunciation_id: i64,
    ipa: Option<&str>,
    audio_url: Option<&str>,
    accent: Option<&str>,
) -> Result<bool> {
    let rows = conn.execute(
        "UPDATE pronunciations SET ipa = ?, audio_url = ?, accent = ? WHERE id = ?",
        params![ipa, audio_url, accent, pronunciation_id],
    )?;
    Ok(rows > 0)
}

/// Update an etymology
pub fn update_etymology(conn: &Connection, etymology_id: i64, text: &str) -> Result<bool> {
    let rows = conn.execute(
        "UPDATE etymologies SET etymology_text = ? WHERE id = ?",
        params![text, etymology_id],
    )?;
    Ok(rows > 0)
}

/// Update a translation
pub fn update_translation(
    conn: &Connection,
    translation_id: i64,
    target_language: &str,
    translation: &str,
) -> Result<bool> {
    let rows = conn.execute(
        "UPDATE translations SET target_language = ?, translation = ? WHERE id = ?",
        params![target_language, translation, translation_id],
    )?;
    Ok(rows > 0)
}

// ============================================================================
// Delete Operations
// ============================================================================

/// Delete a word entry and all associated data (cascades)
pub fn delete_word(conn: &Connection, word_id: i64) -> Result<bool> {
    let rows = conn.execute("DELETE FROM words WHERE id = ?", params![word_id])?;
    Ok(rows > 0)
}

/// Delete a definition
pub fn delete_definition(conn: &Connection, definition_id: i64) -> Result<bool> {
    let rows = conn.execute("DELETE FROM definitions WHERE id = ?", params![definition_id])?;
    Ok(rows > 0)
}

/// Delete a pronunciation
pub fn delete_pronunciation(conn: &Connection, pronunciation_id: i64) -> Result<bool> {
    let rows = conn.execute(
        "DELETE FROM pronunciations WHERE id = ?",
        params![pronunciation_id],
    )?;
    Ok(rows > 0)
}

/// Delete an etymology
pub fn delete_etymology(conn: &Connection, etymology_id: i64) -> Result<bool> {
    let rows = conn.execute("DELETE FROM etymologies WHERE id = ?", params![etymology_id])?;
    Ok(rows > 0)
}

/// Delete a translation
pub fn delete_translation(conn: &Connection, translation_id: i64) -> Result<bool> {
    let rows = conn.execute("DELETE FROM translations WHERE id = ?", params![translation_id])?;
    Ok(rows > 0)
}

// ============================================================================
// Query Operations
// ============================================================================

/// Get a word by ID (basic info only)
pub fn get_word(handle: &DictHandle, word_id: i64) -> Result<Option<crate::models::Word>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, word, pos, language, etymology_num FROM words WHERE id = ?",
    )?;

    match stmt.query_row(params![word_id], |row| {
        Ok(crate::models::Word {
            id: row.get(0)?,
            word: row.get(1)?,
            pos: row.get(2)?,
            language: row.get(3)?,
            etymology_num: row.get(4)?,
        })
    }) {
        Ok(word) => Ok(Some(word)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Get all words matching a specific word string
pub fn get_words_by_word(handle: &DictHandle, word: &str) -> Result<Vec<crate::models::Word>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, word, pos, language, etymology_num FROM words WHERE word = ?",
    )?;

    let rows = stmt.query_map(params![word], |row| {
        Ok(crate::models::Word {
            id: row.get(0)?,
            word: row.get(1)?,
            pos: row.get(2)?,
            language: row.get(3)?,
            etymology_num: row.get(4)?,
        })
    })?;

    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Get all words for a specific language
pub fn get_words_by_language(
    handle: &DictHandle,
    language: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<crate::models::Word>> {
    let mut stmt = handle.conn.prepare(
        "SELECT id, word, pos, language, etymology_num FROM words WHERE language = ? LIMIT ? OFFSET ?",
    )?;

    let rows = stmt.query_map(params![language, limit, offset], |row| {
        Ok(crate::models::Word {
            id: row.get(0)?,
            word: row.get(1)?,
            pos: row.get(2)?,
            language: row.get(3)?,
            etymology_num: row.get(4)?,
        })
    })?;

    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| e.into())
}

/// Get word count for statistics
pub fn get_word_count(handle: &DictHandle) -> Result<i64> {
    let count: i64 = handle
        .conn
        .query_row("SELECT COUNT(*) FROM words", [], |row| row.get(0))?;
    Ok(count)
}

/// Get word count for a specific language
pub fn get_word_count_by_language(handle: &DictHandle, language: &str) -> Result<i64> {
    let count: i64 = handle.conn.query_row(
        "SELECT COUNT(*) FROM words WHERE language = ?",
        params![language],
        |row| row.get(0),
    )?;
    Ok(count)
}

/// Rebuild the FTS index (useful after bulk operations)
pub fn rebuild_fts_index(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        DELETE FROM words_fts;
        INSERT INTO words_fts(rowid, word) SELECT id, word FROM words;
        "#,
    )?;
    Ok(())
}

/// Optimize the FTS index for better search performance
pub fn optimize_fts_index(conn: &Connection) -> Result<()> {
    conn.execute("INSERT INTO words_fts(words_fts) VALUES('optimize')", [])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_test_db() -> (tempfile::TempDir, DictHandle) {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let handle = init_database(db_path.to_str().unwrap()).unwrap();
        (dir, handle)
    }

    #[test]
    fn test_init_database() {
        let (_dir, handle) = setup_test_db();
        
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
        let (_dir, handle) = setup_test_db();

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

    #[test]
    fn test_update_word() {
        let (_dir, handle) = setup_test_db();

        let word_id = insert_word(&handle.conn, "test", "noun", "English", 0).unwrap();
        
        // Update the word
        let updated = update_word(&handle.conn, word_id, "testing", "verb", "English").unwrap();
        assert!(updated);
        
        // Verify the update
        let word = get_word(&handle, word_id).unwrap().unwrap();
        assert_eq!(word.word, "testing");
        assert_eq!(word.pos, "verb");
    }

    #[test]
    fn test_update_definition() {
        let (_dir, handle) = setup_test_db();

        let word_id = insert_word(&handle.conn, "test", "noun", "English", 0).unwrap();
        let def_id = insert_definition(
            &handle.conn,
            word_id,
            "Original definition",
            &[],
            &[],
        )
        .unwrap();
        
        // Update the definition
        let updated = update_definition(
            &handle.conn,
            def_id,
            "Updated definition",
            &["Example sentence".to_string()],
            &["informal".to_string()],
        )
        .unwrap();
        assert!(updated);
        
        // Verify
        let full_def = get_full_definition(&handle, word_id).unwrap().unwrap();
        assert_eq!(full_def.definitions[0].text, "Updated definition");
        assert_eq!(full_def.definitions[0].examples, vec!["Example sentence"]);
    }

    #[test]
    fn test_delete_word_cascades() {
        let (_dir, handle) = setup_test_db();

        let word_id = insert_word(&handle.conn, "test", "noun", "English", 0).unwrap();
        insert_definition(&handle.conn, word_id, "A definition", &[], &[]).unwrap();
        insert_pronunciation(&handle.conn, word_id, Some("/test/"), None, Some("US")).unwrap();
        insert_etymology(&handle.conn, word_id, "From Latin testum").unwrap();
        insert_translation(&handle.conn, word_id, "es", "prueba").unwrap();
        
        // Delete the word
        let deleted = delete_word(&handle.conn, word_id).unwrap();
        assert!(deleted);
        
        // Verify everything is deleted
        let full_def = get_full_definition(&handle, word_id).unwrap();
        assert!(full_def.is_none());
        
        // Verify related data is also deleted
        let def_count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM definitions WHERE word_id = ?",
                params![word_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(def_count, 0);
    }

    #[test]
    fn test_get_words_by_word() {
        let (_dir, handle) = setup_test_db();

        // Insert same word with different parts of speech
        insert_word(&handle.conn, "test", "noun", "English", 0).unwrap();
        insert_word(&handle.conn, "test", "verb", "English", 0).unwrap();
        insert_word(&handle.conn, "other", "noun", "English", 0).unwrap();
        
        let words = get_words_by_word(&handle, "test").unwrap();
        assert_eq!(words.len(), 2);
    }

    #[test]
    fn test_get_word_count() {
        let (_dir, handle) = setup_test_db();

        insert_word(&handle.conn, "hello", "interjection", "English", 0).unwrap();
        insert_word(&handle.conn, "world", "noun", "English", 0).unwrap();
        insert_word(&handle.conn, "bonjour", "interjection", "French", 0).unwrap();
        
        let total = get_word_count(&handle).unwrap();
        assert_eq!(total, 3);
        
        let english_count = get_word_count_by_language(&handle, "English").unwrap();
        assert_eq!(english_count, 2);
    }

    #[test]
    fn test_pronunciations() {
        let (_dir, handle) = setup_test_db();

        let word_id = insert_word(&handle.conn, "hello", "interjection", "English", 0).unwrap();
        
        insert_pronunciation(
            &handle.conn,
            word_id,
            Some("/həˈloʊ/"),
            Some("https://example.com/hello.ogg"),
            Some("US"),
        )
        .unwrap();
        
        insert_pronunciation(
            &handle.conn,
            word_id,
            Some("/həˈləʊ/"),
            None,
            Some("UK"),
        )
        .unwrap();
        
        let full_def = get_full_definition(&handle, word_id).unwrap().unwrap();
        assert_eq!(full_def.pronunciations.len(), 2);
        assert_eq!(full_def.pronunciations[0].ipa.as_deref(), Some("/həˈloʊ/"));
        assert_eq!(full_def.pronunciations[0].accent.as_deref(), Some("US"));
    }

    #[test]
    fn test_translations() {
        let (_dir, handle) = setup_test_db();

        let word_id = insert_word(&handle.conn, "hello", "interjection", "English", 0).unwrap();
        
        insert_translation(&handle.conn, word_id, "es", "hola").unwrap();
        insert_translation(&handle.conn, word_id, "fr", "bonjour").unwrap();
        insert_translation(&handle.conn, word_id, "de", "hallo").unwrap();
        
        let full_def = get_full_definition(&handle, word_id).unwrap().unwrap();
        assert_eq!(full_def.translations.len(), 3);
    }

    #[test]
    fn test_fts_triggers() {
        let (_dir, handle) = setup_test_db();

        // Insert a word
        let word_id = insert_word(&handle.conn, "testing", "noun", "English", 0).unwrap();
        
        // Verify FTS index was updated
        let fts_count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM words_fts WHERE word = 'testing'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(fts_count, 1);
        
        // Update the word
        update_word(&handle.conn, word_id, "tested", "verb", "English").unwrap();
        
        // Verify FTS was updated
        let old_count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM words_fts WHERE word = 'testing'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(old_count, 0);
        
        let new_count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM words_fts WHERE word = 'tested'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(new_count, 1);
        
        // Delete the word
        delete_word(&handle.conn, word_id).unwrap();
        
        // Verify FTS was updated
        let final_count: i64 = handle
            .conn
            .query_row(
                "SELECT COUNT(*) FROM words_fts WHERE word = 'tested'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(final_count, 0);
    }
}
