//! Dictionary preprocessor tool
//!
//! Converts Wiktionary JSONL exports from kaikki.org into optimized SQLite databases.
//!
//! # Usage
//!
//! ```bash
//! dict-preprocessor --input kaikki-english.jsonl --output english-dict.db
//! ```

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use anyhow::{Context, Result};
use clap::Parser;
use indicatif::{ProgressBar, ProgressStyle};



/// Dictionary preprocessor - converts JSONL to SQLite
#[derive(Parser, Debug)]
#[command(name = "dict-preprocessor")]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Input JSONL file path
    #[arg(short, long)]
    input: PathBuf,

    /// Output SQLite database path
    #[arg(short, long)]
    output: PathBuf,

    /// Overwrite existing output file
    #[arg(long, default_value = "false")]
    force: bool,
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

    log::info!("Starting import from {:?} to {:?}", args.input, args.output);

    // Set up progress bar
    let progress = Arc::new(AtomicU64::new(0));
    let total = Arc::new(AtomicU64::new(0));

    let pb = ProgressBar::new(0);
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({eta})")?
            .progress_chars("#>-"),
    );

    let progress_clone = progress.clone();
    let total_clone = total.clone();
    let pb_clone = pb.clone();

    // Run import with progress callback
    let progress_callback = move |current: u64, total_lines: u64| {
        progress_clone.store(current, Ordering::Relaxed);
        
        // Update total on first call
        if total_clone.load(Ordering::Relaxed) == 0 && total_lines > 0 {
            total_clone.store(total_lines, Ordering::Relaxed);
            pb_clone.set_length(total_lines);
        }
        
        pb_clone.set_position(current);
    };

    dict_core::import_jsonl(
        args.output.to_str().context("Invalid output path")?,
        args.input.to_str().context("Invalid input path")?,
        progress_callback,
    )
    .context("Import failed")?;

    pb.finish_with_message("Import complete!");

    log::info!(
        "Successfully imported {} entries to {:?}",
        progress.load(Ordering::Relaxed),
        args.output
    );

    Ok(())
}
