# Wiktionary Dictionary App

A cross-platform dictionary app using Wiktionary data with a Rust core and native Android UI.

## Overview

This project provides an offline-capable dictionary application that leverages the comprehensive data from Wiktionary. The architecture consists of:

- **Rust Core**: SQLite database operations and search logic compiled as a native library
- **Android App**: Jetpack Compose UI with JNI bindings to the Rust core
- **Future**: Web (WASM) and iOS support planned

## Features

- Full-text search with fuzzy matching
- Offline support with pre-built SQLite databases
- Text selection integration (define words from any app)
- Multiple language support
- Pronunciations with IPA
- Etymology information
- Example sentences

## Project Structure

```
dict-app/
├── core/                    # Rust core library
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs           # Public API
│       ├── db.rs            # SQLite operations
│       ├── search.rs        # FTS and fuzzy search
│       ├── models.rs        # Data structures
│       ├── import.rs        # JSONL import logic
│       └── ffi.rs           # C FFI exports
│
├── android/                 # Android application
│   └── app/
│       └── src/main/
│           ├── java/        # Kotlin source files
│           ├── jniLibs/     # Compiled .so files
│           └── AndroidManifest.xml
│
├── tools/                   # Build-time tools
│   ├── preprocessor/        # JSONL to SQLite converter
│   └── scripts/             # Build and data scripts
│
└── data/                    # Downloaded/processed data (gitignored)
    ├── raw/
    └── processed/
```

## Prerequisites

### Rust Core Development

- [Rust](https://rustup.rs/) (latest stable)
- Android NDK (for cross-compilation)
- cargo-ndk: `cargo install cargo-ndk`

### Android Development

- Android Studio (latest)
- Android SDK (API 24+)
- Kotlin 1.9+

## Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd dict-app
```

### 2. Install Rust Targets for Android

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
```

### 3. Build the Rust Core

```bash
cd core
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../android/app/src/main/jniLibs build --release
```

### 4. Build the Android App

Open the `android/` directory in Android Studio and build/run as usual.

## Data Source

Dictionary data is sourced from [Kaikki.org](https://kaikki.org/dictionary/rawdata.html), which provides Wiktionary extracts in JSONL format.

### Preprocessing

The `tools/preprocessor` converts JSONL data into optimized SQLite databases:

```bash
cd tools/preprocessor
cargo run --release -- --input ../../data/raw/kaikki-english.jsonl --output ../../data/processed/english-dict.db
```

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed technical documentation including:

- Database schema
- API design
- JNI bindings
- Build process
- Performance targets

## Contributing

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `cargo test` (in `core/`)
5. Submit a pull request

### Code Style

- **Rust**: Follow standard Rust conventions, use `cargo fmt` and `cargo clippy`
- **Kotlin**: Follow [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)

### Issue Tracking

This project uses `bd` (beads) for issue tracking. Run `bd ready` to find available work.

## License

[TBD]

## Acknowledgments

- [Wiktionary](https://www.wiktionary.org/) for the dictionary data
- [Kaikki.org](https://kaikki.org/) for providing machine-readable Wiktionary extracts
