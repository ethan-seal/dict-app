//! Data models for dictionary entries
//!
//! This module defines the core data structures used throughout the application
//! to represent dictionary entries, definitions, pronunciations, and search results.

use serde::{Deserialize, Serialize};

/// A search result entry returned from search queries
///
/// Contains basic information about a word match, suitable for
/// displaying in a search results list.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Unique identifier for this word entry
    pub id: i64,
    /// The word itself
    pub word: String,
    /// Part of speech (noun, verb, adjective, etc.)
    pub pos: String,
    /// Preview text (first definition, truncated)
    pub preview: String,
    /// Relevance score (lower is better, 0 = exact match)
    #[serde(default)]
    pub score: f64,
}

/// A word entry from the database
///
/// Represents the basic word record without definitions or other related data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Word {
    /// Unique identifier for this word entry
    pub id: i64,
    /// The word itself
    pub word: String,
    /// Part of speech (noun, verb, adjective, etc.)
    pub pos: String,
    /// Language of the word
    pub language: String,
    /// Etymology number for words with multiple etymologies
    pub etymology_num: i32,
}

/// A complete definition entry for a word
///
/// Contains all information about a word including all meanings,
/// pronunciations, etymology, and translations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FullDefinition {
    /// The word itself
    pub word: String,
    /// Part of speech (noun, verb, adjective, etc.)
    pub pos: String,
    /// Language of the word
    pub language: String,
    /// Language code (e.g. "en", "fr")
    pub lang_code: String,
    /// List of definitions/meanings
    pub definitions: Vec<Definition>,
    /// Pronunciation information
    pub pronunciations: Vec<Pronunciation>,
    /// Etymology text, if available
    pub etymology: Option<String>,
    /// Translations to other languages
    pub translations: Vec<Translation>,
}

/// A single definition/meaning of a word
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Definition {
    /// Unique identifier for this definition
    pub id: i64,
    /// The definition text
    pub text: String,
    /// Example sentences demonstrating usage
    pub examples: Vec<String>,
    /// Tags/labels (formal, slang, archaic, etc.)
    pub tags: Vec<String>,
}

/// Pronunciation information for a word
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pronunciation {
    /// Unique identifier
    pub id: i64,
    /// IPA transcription
    pub ipa: Option<String>,
    /// URL to audio file, if available
    pub audio_url: Option<String>,
    /// Regional accent (US, UK, AU, etc.)
    pub accent: Option<String>,
}

/// A translation of a word to another language
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Translation {
    /// Unique identifier
    pub id: i64,
    /// Target language code
    pub target_language: String,
    /// The translated word/phrase
    pub translation: String,
}

/// Raw word entry from JSONL import
///
/// This structure matches the format of entries in the Wiktionary JSONL export.
/// Used during the import process to parse raw data before inserting into SQLite.
#[derive(Debug, Clone, Deserialize)]
pub struct RawWordEntry {
    /// The word being defined
    pub word: String,
    /// Part of speech
    pub pos: String,
    /// Language of the entry
    #[serde(default = "default_language")]
    pub lang: String,
    /// Language code
    #[serde(default)]
    pub lang_code: String,
    /// Etymology number for words with multiple etymologies
    #[serde(default)]
    pub etymology_number: Option<i32>,
    /// Etymology text
    #[serde(default)]
    pub etymology_text: Option<String>,
    /// List of senses/definitions
    #[serde(default)]
    pub senses: Vec<RawSense>,
    /// Pronunciation information
    #[serde(default)]
    pub sounds: Vec<RawSound>,
    /// Translations
    #[serde(default)]
    pub translations: Vec<RawTranslation>,
}

fn default_language() -> String {
    "English".to_string()
}

/// A raw sense/definition from JSONL
#[derive(Debug, Clone, Deserialize)]
pub struct RawSense {
    /// The definition text (may contain wiki markup)
    #[serde(default)]
    pub glosses: Vec<String>,
    /// Raw glosses without cleanup
    #[serde(default)]
    pub raw_glosses: Vec<String>,
    /// Example sentences
    #[serde(default)]
    pub examples: Vec<RawExample>,
    /// Tags/labels
    #[serde(default)]
    pub tags: Vec<String>,
}

/// A raw example from JSONL
#[derive(Debug, Clone, Deserialize)]
pub struct RawExample {
    /// The example text
    #[serde(default)]
    pub text: String,
}

/// Raw pronunciation/sound from JSONL
#[derive(Debug, Clone, Deserialize)]
pub struct RawSound {
    /// IPA transcription
    #[serde(default)]
    pub ipa: Option<String>,
    /// Audio file URL
    #[serde(default)]
    pub audio: Option<String>,
    /// OGG audio URL
    #[serde(default)]
    pub ogg_url: Option<String>,
    /// MP3 audio URL
    #[serde(default)]
    pub mp3_url: Option<String>,
    /// Regional tags
    #[serde(default)]
    pub tags: Vec<String>,
}

/// Raw translation from JSONL
#[derive(Debug, Clone, Deserialize)]
pub struct RawTranslation {
    /// Target language
    #[serde(default)]
    pub lang: String,
    /// Target language code
    #[serde(default)]
    pub code: String,
    /// The translation
    #[serde(default)]
    pub word: String,
}

impl SearchResult {
    /// Create a new SearchResult
    pub fn new(id: i64, word: String, pos: String, preview: String) -> Self {
        Self {
            id,
            word,
            pos,
            preview,
            score: 0.0,
        }
    }

    /// Create a new SearchResult with a score
    pub fn with_score(id: i64, word: String, pos: String, preview: String, score: f64) -> Self {
        Self {
            id,
            word,
            pos,
            preview,
            score,
        }
    }
}

impl FullDefinition {
    /// Create a new empty FullDefinition
    pub fn new(word: String, pos: String, language: String, lang_code: String) -> Self {
        Self {
            word,
            pos,
            language,
            lang_code,
            definitions: Vec::new(),
            pronunciations: Vec::new(),
            etymology: None,
            translations: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_search_result_new() {
        let result = SearchResult::new(
            1,
            "hello".to_string(),
            "interjection".to_string(),
            "A greeting".to_string(),
        );
        assert_eq!(result.id, 1);
        assert_eq!(result.word, "hello");
    }

    #[test]
    fn test_raw_word_entry_deserialize() {
        let json = r#"{
            "word": "test",
            "pos": "noun",
            "senses": [{"glosses": ["A trial"]}]
        }"#;
        let entry: RawWordEntry = serde_json::from_str(json).unwrap();
        assert_eq!(entry.word, "test");
        assert_eq!(entry.pos, "noun");
        assert_eq!(entry.lang, "English"); // default
    }
}
