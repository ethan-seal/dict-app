-- Dictionary database schema
-- This file is included at compile time by import.rs

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
