//! Dictionary preprocessor tool
//!
//! Converts Wiktionary JSONL exports from kaikki.org into optimized SQLite databases.
//!
//! # Usage
//!
//! ```bash
//! # Raw JSONL file
//! dict-preprocessor --input kaikki-english.jsonl --output english-dict.db
//!
//! # Gzip-compressed JSONL file
//! dict-preprocessor --input kaikki-english.jsonl.gz --output english-dict.db
//! ```

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use clap::Parser;
use indicatif::{HumanBytes, HumanDuration, ProgressBar, ProgressStyle};

/// Dictionary preprocessor - converts Wiktionary JSONL to SQLite
#[derive(Parser, Debug)]
#[command(name = "dict-preprocessor")]
#[command(author, version, about = "Convert Wiktionary JSONL exports to optimized SQLite databases")]
#[command(long_about = "
Converts Wiktionary JSONL exports from kaikki.org into optimized SQLite databases.

Supports both raw JSONL files and gzip-compressed files (.jsonl.gz).

Example usage:
  dict-preprocessor -i kaikki-english.jsonl.gz -o english.db
  dict-preprocessor --input data.jsonl --output dict.db --force
")]
struct Args {
    /// Input JSONL file path (supports .jsonl and .jsonl.gz)
    #[arg(short, long)]
    input: PathBuf,

    /// Output SQLite database path
    #[arg(short, long)]
    output: PathBuf,

    /// Overwrite existing output file
    #[arg(long, default_value = "false")]
    force: bool,

    /// Quiet mode - suppress progress bar
    #[arg(short, long, default_value = "false")]
    quiet: bool,
}

fn main() -> Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let args = Args::parse();

    // Validate input file exists
    if !args.input.exists() {
        anyhow::bail!("Input file does not exist: {:?}", args.input);
    }

    // Check if output exists
    if args.output.exists() && !args.force {
        anyhow::bail!(
            "Output file already exists: {:?}. Use --force to overwrite.",
            args.output
        );
    }

    // Remove existing output if force is set
    if args.output.exists() && args.force {
        std::fs::remove_file(&args.output)
            .context("Failed to remove existing output file")?;
    }

    // Get input file size for reporting
    let input_size = std::fs::metadata(&args.input)
        .map(|m| m.len())
        .unwrap_or(0);

    println!("Input:  {:?} ({})", args.input, HumanBytes(input_size));
    println!("Output: {:?}", args.output);
    println!();

    log::info!("Starting import from {:?} to {:?}", args.input, args.output);

    let start_time = Instant::now();

    // Set up progress bar
    let total = Arc::new(AtomicU64::new(0));

    let pb = if args.quiet {
        ProgressBar::hidden()
    } else {
        ProgressBar::new(0)
    };
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} lines ({eta})")?
            .progress_chars("#>-"),
    );

    let total_clone = total.clone();
    let pb_clone = pb.clone();

    // Run import with progress callback
    let progress_callback = move |current: u64, total_lines: u64| {
        // Update total on first call
        if total_clone.load(Ordering::Relaxed) == 0 && total_lines > 0 {
            total_clone.store(total_lines, Ordering::Relaxed);
            pb_clone.set_length(total_lines);
        }

        pb_clone.set_position(current);
    };

    let stats = dict_core::import_jsonl_with_stats(
        args.output.to_str().context("Invalid output path")?,
        args.input.to_str().context("Invalid input path")?,
        progress_callback,
    )
    .context("Import failed")?;

    pb.finish_and_clear();

    let elapsed = start_time.elapsed();

    // Get output file size
    let output_size = std::fs::metadata(&args.output)
        .map(|m| m.len())
        .unwrap_or(0);

    // Print statistics
    println!("Import complete!");
    println!();
    println!("Statistics:");
    println!("  Lines processed:    {:>12}", format_number(stats.lines_processed));
    println!("  Words imported:     {:>12}", format_number(stats.words_imported));
    println!("  Definitions:        {:>12}", format_number(stats.definitions_imported));
    println!("  Pronunciations:     {:>12}", format_number(stats.pronunciations_imported));
    println!("  Etymologies:        {:>12}", format_number(stats.etymologies_imported));
    println!("  Translations:       {:>12}", format_number(stats.translations_imported));
    println!("  Errors:             {:>12}", format_number(stats.errors));
    println!("  Skipped:            {:>12}", format_number(stats.skipped));
    println!();
    println!("Performance:");
    println!("  Time elapsed:       {:>12}", HumanDuration(elapsed));
    println!("  Output size:        {:>12}", HumanBytes(output_size));

    if elapsed.as_secs() > 0 {
        let lines_per_sec = stats.lines_processed / elapsed.as_secs();
        println!("  Lines/second:       {:>12}", format_number(lines_per_sec));
    }

    log::info!(
        "Successfully imported {} words to {:?} in {:?}",
        stats.words_imported,
        args.output,
        elapsed
    );

    Ok(())
}

/// Format a number with thousand separators
fn format_number(n: u64) -> String {
    let s = n.to_string();
    let mut result = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.push(',');
        }
        result.push(c);
    }
    result.chars().rev().collect()
}
