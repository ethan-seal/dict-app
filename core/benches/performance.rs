//! Performance benchmarks for dict-core
//!
//! Run with: `cargo bench -p dict-core`
//!
//! Performance targets (from ARCHITECTURE.md):
//! - Cold startup (DB exists): < 500ms
//! - Search latency: < 50ms
//! - Definition load: < 20ms

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use dict_core::{get_definition, import_jsonl, init, search};
use std::io::Write;
use std::time::Duration;

// ============================================================================
// Test Data Setup
// ============================================================================

/// Sample JSONL entries for realistic dictionary data
const SAMPLE_ENTRIES: &[&str] = &[
    r#"{"word":"hello","pos":"interjection","lang":"English","senses":[{"glosses":["A greeting used to begin a conversation"]},{"glosses":["Used to express surprise"]}]}"#,
    r#"{"word":"help","pos":"verb","lang":"English","senses":[{"glosses":["To give assistance to someone"]}],"sounds":[{"ipa":"/hɛlp/"}]}"#,
    r#"{"word":"helper","pos":"noun","lang":"English","senses":[{"glosses":["A person who helps"]}]}"#,
    r#"{"word":"helping","pos":"noun","lang":"English","senses":[{"glosses":["A portion of food"]}]}"#,
    r#"{"word":"helicopter","pos":"noun","lang":"English","senses":[{"glosses":["An aircraft with rotating blades"]}],"etymology_text":"From Greek helix + pteron"}"#,
    r#"{"word":"heliocentric","pos":"adjective","lang":"English","senses":[{"glosses":["Having the sun as center"]}]}"#,
    r#"{"word":"world","pos":"noun","lang":"English","senses":[{"glosses":["The earth and its inhabitants"]},{"glosses":["A realm or domain"]}]}"#,
    r#"{"word":"word","pos":"noun","lang":"English","senses":[{"glosses":["A unit of language"]}],"sounds":[{"ipa":"/wɜːd/","tags":["UK"]},{"ipa":"/wɝd/","tags":["US"]}]}"#,
    r#"{"word":"work","pos":"verb","lang":"English","senses":[{"glosses":["To engage in activity"]},{"glosses":["To function correctly"]}]}"#,
    r#"{"word":"worker","pos":"noun","lang":"English","senses":[{"glosses":["One who works"]}]}"#,
    r#"{"word":"test","pos":"noun","lang":"English","senses":[{"glosses":["A procedure for evaluation"]}]}"#,
    r#"{"word":"testing","pos":"verb","lang":"English","senses":[{"glosses":["Conducting tests"]}]}"#,
    r#"{"word":"example","pos":"noun","lang":"English","senses":[{"glosses":["Something representative"]}]}"#,
    r#"{"word":"dictionary","pos":"noun","lang":"English","senses":[{"glosses":["A reference book of words"]}],"etymology_text":"From Medieval Latin dictionarium"}"#,
    r#"{"word":"language","pos":"noun","lang":"English","senses":[{"glosses":["A system of communication"]}]}"#,
    r#"{"word":"definition","pos":"noun","lang":"English","senses":[{"glosses":["A statement of meaning"]}]}"#,
    r#"{"word":"search","pos":"verb","lang":"English","senses":[{"glosses":["To look carefully for"]}]}"#,
    r#"{"word":"find","pos":"verb","lang":"English","senses":[{"glosses":["To discover or locate"]}]}"#,
    r#"{"word":"result","pos":"noun","lang":"English","senses":[{"glosses":["A consequence or outcome"]}]}"#,
    r#"{"word":"performance","pos":"noun","lang":"English","senses":[{"glosses":["Execution of an action"]}]}"#,
];

/// Create a test database with realistic data using JSONL import
fn create_test_db(word_count: usize) -> (tempfile::TempDir, String) {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("bench.db");
    let jsonl_path = dir.path().join("data.jsonl");

    // Generate JSONL content
    let mut file = std::fs::File::create(&jsonl_path).unwrap();
    for i in 0..word_count {
        let base_entry = SAMPLE_ENTRIES[i % SAMPLE_ENTRIES.len()];
        if i < SAMPLE_ENTRIES.len() {
            writeln!(file, "{}", base_entry).unwrap();
        } else {
            // Create variations for larger datasets
            let suffix = i / SAMPLE_ENTRIES.len();
            let modified =
                base_entry.replacen("\"word\":\"", &format!("\"word\":\"{}_", suffix), 1);
            writeln!(file, "{}", modified).unwrap();
        }
    }
    drop(file);

    // Import the JSONL data
    import_jsonl(
        db_path.to_str().unwrap(),
        jsonl_path.to_str().unwrap(),
        |_, _| {},
    )
    .unwrap();

    let db_path_str = db_path.to_str().unwrap().to_string();
    (dir, db_path_str)
}

/// Create a medium test database for realistic benchmarks
fn create_medium_db() -> (tempfile::TempDir, String) {
    create_test_db(1000)
}

// ============================================================================
// Startup Time Benchmarks
// ============================================================================

fn bench_startup(c: &mut Criterion) {
    let mut group = c.benchmark_group("startup");
    group.measurement_time(Duration::from_secs(10));

    // Test with different database sizes
    for (name, word_count) in [
        ("small_100", 100),
        ("medium_1k", 1000),
        ("large_10k", 10000),
    ] {
        let (_dir, db_path) = create_test_db(word_count);

        group.bench_with_input(BenchmarkId::new("init", name), &db_path, |b, db_path| {
            b.iter(|| {
                let handle = init(black_box(db_path)).unwrap();
                black_box(handle)
            });
        });
    }

    group.finish();
}

// ============================================================================
// FTS5 Search Benchmarks
// ============================================================================

fn bench_fts_search(c: &mut Criterion) {
    let mut group = c.benchmark_group("fts_search");
    group.measurement_time(Duration::from_secs(10));

    let (_dir, db_path) = create_medium_db();
    let handle = init(&db_path).unwrap();

    // Different query types
    let queries = [
        ("exact_match", "hello"),
        ("prefix_short", "hel"),
        ("prefix_long", "helicop"),
        ("common_word", "the"),
        ("no_match", "xyzzy"),
        ("multi_word", "hello world"),
    ];

    for (name, query) in queries {
        group.bench_with_input(BenchmarkId::new("query", name), &query, |b, query| {
            b.iter(|| search(black_box(&handle), black_box(query), 50));
        });
    }

    // Different result limits
    for limit in [10, 50, 100] {
        group.bench_with_input(BenchmarkId::new("limit", limit), &limit, |b, &limit| {
            b.iter(|| search(black_box(&handle), "hel", black_box(limit)));
        });
    }

    group.finish();
}

fn bench_fts_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("fts_scaling");
    group.measurement_time(Duration::from_secs(15));

    // Test search performance with different database sizes
    for (name, word_count) in [("100_words", 100), ("1k_words", 1000), ("10k_words", 10000)] {
        let (_dir, db_path) = create_test_db(word_count);
        let handle = init(&db_path).unwrap();

        group.throughput(Throughput::Elements(1));
        group.bench_with_input(BenchmarkId::new("search", name), &handle, |b, handle| {
            b.iter(|| search(black_box(handle), "hel", 50));
        });

        // Keep handle alive for benchmark
        drop(handle);
    }

    group.finish();
}

// ============================================================================
// Fuzzy Search (Levenshtein) Benchmarks
// ============================================================================

fn bench_levenshtein(c: &mut Criterion) {
    let mut group = c.benchmark_group("levenshtein");

    // Direct algorithm benchmarks using the search module
    // We test via search() with typos that trigger fuzzy matching
    let (_dir, db_path) = create_medium_db();
    let handle = init(&db_path).unwrap();

    // Queries with typos that should trigger fuzzy matching
    let typo_queries = [
        ("single_typo", "helo"),    // hello with missing l
        ("transposition", "hlelo"), // hello with transposition
        ("substitution", "hallo"),  // hello with substitution
        ("common_typo", "wrold"),   // world with transposition
        ("double_typo", "halp"),    // help with substitution
    ];

    for (name, query) in typo_queries {
        group.bench_with_input(
            BenchmarkId::new("fuzzy_search", name),
            &query,
            |b, query| {
                b.iter(|| search(black_box(&handle), black_box(query), 50));
            },
        );
    }

    group.finish();
}

// ============================================================================
// Definition Loading Benchmarks
// ============================================================================

fn bench_definition_loading(c: &mut Criterion) {
    let mut group = c.benchmark_group("definition_loading");
    group.measurement_time(Duration::from_secs(10));

    let (_dir, db_path) = create_medium_db();
    let handle = init(&db_path).unwrap();

    // Get some word IDs to test with
    let results = search(&handle, "hello", 10);
    let word_id = results.first().map(|r| r.id).unwrap_or(1);

    // Single definition load
    group.bench_function("single_definition", |b| {
        b.iter(|| get_definition(black_box(&handle), black_box(word_id)));
    });

    // Batch definition loading (simulates scrolling through results)
    let word_ids: Vec<i64> = search(&handle, "hel", 20).iter().map(|r| r.id).collect();

    group.bench_function("batch_10_definitions", |b| {
        b.iter(|| {
            for &id in word_ids.iter().take(10) {
                black_box(get_definition(&handle, id));
            }
        });
    });

    group.bench_function("batch_20_definitions", |b| {
        b.iter(|| {
            for &id in &word_ids {
                black_box(get_definition(&handle, id));
            }
        });
    });

    group.finish();
}

// ============================================================================
// Import Throughput Benchmarks
// ============================================================================

fn bench_import(c: &mut Criterion) {
    let mut group = c.benchmark_group("import");
    group.measurement_time(Duration::from_secs(20));
    group.sample_size(10); // Fewer samples due to longer runtime

    // Test import with different batch sizes
    for count in [100, 500] {
        group.throughput(Throughput::Elements(count as u64));

        group.bench_with_input(
            BenchmarkId::new("jsonl_import", format!("{}_entries", count)),
            &count,
            |b, &count| {
                b.iter_with_setup(
                    || {
                        // Setup: create temp files
                        let dir = tempfile::tempdir().unwrap();
                        let db_path = dir.path().join("import_bench.db");
                        let jsonl_path = dir.path().join("data.jsonl");

                        // Write JSONL content
                        let mut file = std::fs::File::create(&jsonl_path).unwrap();
                        for i in 0..count {
                            let base_entry = SAMPLE_ENTRIES[i % SAMPLE_ENTRIES.len()];
                            let modified = base_entry.replacen(
                                "\"word\":\"",
                                &format!("\"word\":\"bench{}_", i),
                                1,
                            );
                            writeln!(file, "{}", modified).unwrap();
                        }
                        drop(file);

                        (dir, db_path, jsonl_path)
                    },
                    |(_dir, db_path, jsonl_path)| {
                        import_jsonl(
                            db_path.to_str().unwrap(),
                            jsonl_path.to_str().unwrap(),
                            |_, _| {},
                        )
                        .unwrap();
                    },
                );
            },
        );
    }

    group.finish();
}

// ============================================================================
// End-to-End Benchmarks
// ============================================================================

fn bench_e2e_flow(c: &mut Criterion) {
    let mut group = c.benchmark_group("e2e_flow");
    group.measurement_time(Duration::from_secs(15));

    // Benchmark: Complete user flow (startup -> search -> load definition)
    let (_dir, db_path) = create_medium_db();

    group.bench_function("cold_start_search_definition", |b| {
        b.iter(|| {
            // 1. Initialize (simulates app startup)
            let handle = init(black_box(&db_path)).unwrap();

            // 2. Search for a word
            let results = search(&handle, "hello", 10);

            // 3. Load the first definition
            if let Some(result) = results.first() {
                black_box(get_definition(&handle, result.id));
            }
        });
    });

    // Benchmark: Warm search flow (handle already initialized)
    let handle = init(&db_path).unwrap();

    group.bench_function("warm_search_and_definition", |b| {
        b.iter(|| {
            // Search
            let results = search(black_box(&handle), "help", 10);

            // Load definition
            if let Some(result) = results.first() {
                black_box(get_definition(&handle, result.id));
            }
        });
    });

    // Benchmark: Rapid search (typing simulation - multiple searches)
    group.bench_function("rapid_typing_simulation", |b| {
        let typing_sequence = ["h", "he", "hel", "hell", "hello"];
        b.iter(|| {
            for query in &typing_sequence {
                black_box(search(&handle, query, 10));
            }
        });
    });

    // Benchmark: Browse results (search then load multiple definitions)
    group.bench_function("browse_results_10", |b| {
        b.iter(|| {
            let results = search(black_box(&handle), "hel", 10);
            for result in &results {
                black_box(get_definition(&handle, result.id));
            }
        });
    });

    group.finish();
}

// ============================================================================
// Memory-Related Benchmarks
// ============================================================================

fn bench_repeated_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("repeated_operations");
    group.measurement_time(Duration::from_secs(10));

    let (_dir, db_path) = create_medium_db();
    let handle = init(&db_path).unwrap();

    // Many searches in sequence (tests for memory leaks in FFI layer)
    group.bench_function("100_sequential_searches", |b| {
        b.iter(|| {
            for i in 0..100 {
                let query = ["hello", "world", "help", "test", "word"][i % 5];
                black_box(search(&handle, query, 20));
            }
        });
    });

    // Alternating search and definition loads
    group.bench_function("50_search_definition_pairs", |b| {
        b.iter(|| {
            for _ in 0..50 {
                let results = search(&handle, "hel", 5);
                if let Some(r) = results.first() {
                    black_box(get_definition(&handle, r.id));
                }
            }
        });
    });

    group.finish();
}

// ============================================================================
// Criterion Configuration
// ============================================================================

criterion_group!(
    benches,
    bench_startup,
    bench_fts_search,
    bench_fts_scaling,
    bench_levenshtein,
    bench_definition_loading,
    bench_import,
    bench_e2e_flow,
    bench_repeated_operations,
);

criterion_main!(benches);
