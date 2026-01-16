# Wiktionary Dictionary App - Architecture Plan

## Overview

Cross-platform dictionary app using Wiktionary data with:
- **Rust core**: SQLite database + search logic
- **Android UI**: Jetpack Compose + JNI bindings
- **Web**: WASM compilation (future)
- **iOS**: Native compilation via FFI (future)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Rust Core                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   SQLite    │  │  Search/FTS │  │   Data Models       │  │
│  │  (rusqlite) │  │   Engine    │  │ (Word, Definition)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                           │                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Public API (C FFI)                         ││
│  │  - init_database(path)                                  ││
│  │  - search_word(query) -> Vec<WordEntry>                 ││
│  │  - get_definition(word_id) -> FullDefinition            ││
│  │  - import_jsonl(path, progress_callback)                ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
          │                    │                    │
     ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
     │ Android │          │   Web   │          │   iOS   │
     │  (JNI)  │          │ (WASM)  │          │  (FFI)  │
     └────┬────┘          └─────────┘          └─────────┘
          │
┌─────────┴─────────────────────────────────────────┐
│              Android Application                   │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │
│  │  Compose UI │  │  ViewModel  │  │ Download  │  │
│  │  - Search   │  │  - State    │  │  Manager  │  │
│  │  - Results  │  │  - Flow     │  │  - OkHttp │  │
│  │  - Detail   │  │             │  │  - Import │  │
│  └─────────────┘  └─────────────┘  └───────────┘  │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │  Text Selection Integration                │   │
│  │  ACTION_PROCESS_TEXT Activity              │   │
│  └────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

## Data Pipeline

### Source Data
- **URL**: https://kaikki.org/dictionary/rawdata.html
- **Format**: JSONL (one JSON object per line)
- **Size**: ~500MB-1GB compressed per language

### Preprocessing (Build-time, on server or CI)

Convert Wiktionary JSONL to optimized SQLite:

```
kaikki-english.jsonl.gz
        │
        ▼
┌───────────────────┐
│  Preprocessing    │
│  Script (Rust)    │
│  - Parse JSONL    │
│  - Normalize      │
│  - Build FTS      │
└───────────────────┘
        │
        ▼
english-dict.db.zst  (~200-400MB compressed)
```

### Runtime Flow (First Launch)

```
1. App Launch
       │
       ▼
2. Check for local DB
       │ (not found)
       ▼
3. Show language picker
       │
       ▼
4. Download compressed .db from CDN
       │ (show progress)
       ▼
5. Decompress to app storage
       │
       ▼
6. Initialize Rust core with DB path
       │
       ▼
7. Ready to search
```

## Database Schema

```sql
-- Main word entries
CREATE TABLE words (
    id INTEGER PRIMARY KEY,
    word TEXT NOT NULL,
    pos TEXT NOT NULL,              -- part of speech
    language TEXT NOT NULL,
    etymology_num INTEGER DEFAULT 0 -- for words with multiple etymologies
);

CREATE INDEX idx_words_word ON words(word);
CREATE INDEX idx_words_language ON words(language);

-- Full-text search
CREATE VIRTUAL TABLE words_fts USING fts5(
    word,
    content='words',
    content_rowid='id'
);

-- Definitions (one word can have many)
CREATE TABLE definitions (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL REFERENCES words(id),
    definition TEXT NOT NULL,
    examples TEXT,                  -- JSON array
    tags TEXT,                      -- JSON array (formal, slang, etc.)
    FOREIGN KEY (word_id) REFERENCES words(id)
);

CREATE INDEX idx_definitions_word_id ON definitions(word_id);

-- Pronunciations
CREATE TABLE pronunciations (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    ipa TEXT,
    audio_url TEXT,
    accent TEXT,                    -- e.g., "US", "UK", "AU"
    FOREIGN KEY (word_id) REFERENCES words(id)
);

-- Etymology
CREATE TABLE etymologies (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    etymology_text TEXT NOT NULL,
    FOREIGN KEY (word_id) REFERENCES words(id)
);

-- Translations (for multi-language support)
CREATE TABLE translations (
    id INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL,
    target_language TEXT NOT NULL,
    translation TEXT NOT NULL,
    FOREIGN KEY (word_id) REFERENCES words(id)
);

CREATE INDEX idx_translations_word_id ON translations(word_id);
CREATE INDEX idx_translations_language ON translations(target_language);
```

## Project Structure

```
dict-app/
├── core/                          # Rust core library
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs                 # Public API
│   │   ├── db.rs                  # SQLite operations
│   │   ├── search.rs              # FTS and fuzzy search
│   │   ├── models.rs              # Data structures
│   │   ├── import.rs              # JSONL import logic
│   │   └── ffi.rs                 # C FFI exports
│   └── build.rs                   # Build configuration
│
├── android/                       # Android application
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/.../
│   │   │   │   ├── MainActivity.kt
│   │   │   │   ├── DefineWordActivity.kt    # PROCESS_TEXT handler
│   │   │   │   ├── DictCore.kt              # JNI bindings
│   │   │   │   ├── ui/
│   │   │   │   │   ├── SearchScreen.kt
│   │   │   │   │   ├── DefinitionScreen.kt
│   │   │   │   │   └── DownloadScreen.kt
│   │   │   │   └── viewmodel/
│   │   │   │       └── DictViewModel.kt
│   │   │   ├── jniLibs/                     # Compiled .so files
│   │   │   └── AndroidManifest.xml
│   │   └── build.gradle.kts
│   └── build.gradle.kts
│
├── tools/                         # Build-time tools
│   ├── preprocessor/              # Rust tool to convert JSONL → SQLite
│   │   ├── Cargo.toml
│   │   └── src/main.rs
│   └── scripts/
│       ├── build-android.sh       # Cross-compile for Android
│       └── download-data.sh       # Fetch from kaikki.org
│
└── data/                          # Downloaded/processed data (gitignored)
    ├── raw/
    └── processed/
```

## Rust Core API

```rust
// core/src/lib.rs

/// Initialize the dictionary with a database path
pub fn init(db_path: &str) -> Result<DictHandle, Error>;

/// Search for words (returns top N matches)
pub fn search(handle: &DictHandle, query: &str, limit: u32) -> Vec<SearchResult>;

/// Get full definition for a word
pub fn get_definition(handle: &DictHandle, word_id: i64) -> Option<FullDefinition>;

/// Import JSONL data (for building DB)
pub fn import_jsonl(
    db_path: &str,
    jsonl_path: &str,
    progress: impl Fn(u64, u64),  // (current, total)
) -> Result<(), Error>;

// Data structures
pub struct SearchResult {
    pub id: i64,
    pub word: String,
    pub pos: String,
    pub preview: String,  // First definition, truncated
}

pub struct FullDefinition {
    pub word: String,
    pub pos: String,
    pub definitions: Vec<Definition>,
    pub pronunciations: Vec<Pronunciation>,
    pub etymology: Option<String>,
    pub translations: Vec<Translation>,
}
```

## Android JNI Bindings

```kotlin
// DictCore.kt
object DictCore {
    init {
        System.loadLibrary("dict_core")
    }

    external fun init(dbPath: String): Long  // Returns handle
    external fun search(handle: Long, query: String, limit: Int): Array<SearchResult>
    external fun getDefinition(handle: Long, wordId: Long): FullDefinition?
    external fun close(handle: Long)
}

// Usage in ViewModel
class DictViewModel : ViewModel() {
    private var handle: Long = 0

    fun initialize(dbPath: String) {
        handle = DictCore.init(dbPath)
    }

    fun search(query: String): Flow<List<SearchResult>> = flow {
        emit(DictCore.search(handle, query, 50).toList())
    }
}
```

## Text Selection Integration

```xml
<!-- AndroidManifest.xml -->
<activity
    android:name=".DefineWordActivity"
    android:label="Define"
    android:theme="@style/Theme.Dialog"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.PROCESS_TEXT" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="text/plain" />
    </intent-filter>
</activity>
```

```kotlin
// DefineWordActivity.kt
class DefineWordActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val selectedText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?.toString()
            ?.trim()
            ?: return finish()

        setContent {
            QuickDefinitionDialog(
                word = selectedText,
                onDismiss = { finish() }
            )
        }
    }
}
```

## Build & Cross-Compilation

### Android Targets

```bash
# Install targets
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Build with cargo-ndk
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ./android/app/src/main/jniLibs build --release
```

### Cargo.toml

```toml
[package]
name = "dict-core"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
jni = "0.21"
thiserror = "1.0"

[target.'cfg(target_os = "android")'.dependencies]
android_logger = "0.13"
log = "0.4"
```

## First Launch Flow

1. **Splash Screen**: Check if DB exists
2. **Language Selection**: User picks languages to download
3. **Download Screen**:
   - Show progress bar
   - Download `.db.zst` from CDN
   - Decompress with zstd
   - Verify integrity (checksum)
4. **Initialize Core**: Pass DB path to Rust
5. **Main Screen**: Ready to search

## Performance Targets

| Metric | Target |
|--------|--------|
| Cold startup (DB exists) | < 500ms |
| Search latency | < 50ms |
| Definition load | < 20ms |
| Download size (English) | ~300MB |
| Installed size (English) | ~800MB |

## Future Enhancements

- [ ] Offline audio pronunciation playback
- [ ] Bookmarks/favorites
- [ ] Search history
- [ ] Word of the day widget
- [ ] Multiple language support
- [ ] Spaced repetition for vocabulary learning
- [ ] Web version (WASM)
- [ ] iOS version
